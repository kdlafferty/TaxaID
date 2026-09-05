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
#'   predicates. Default \code{"2000"} through the current year, computed
#'   at call time -- not a fixed year that would silently go stale.
#' @param limit Integer or \code{NULL}. Maximum records to retain
#'   \strong{per taxon key} after import, matching the per-key semantics of
#'   \code{\link{fetch_gbif_occurrences}}. Records are kept in GBIF's return
#'   order; a message reports how many keys were truncated. \code{NULL}
#'   (default) retains all records for every key. When \code{taxonKey} is
#'   absent from the download, the cap is applied to the total row count
#'   instead, with a warning.
#' @param on_cap Character. What to do when `limit` actually truncates a
#'   taxon key. `"warn"` (default) raises a warning naming the affected keys
#'   and records them in `attr(result, "capped_keys")`; `"error"` stops.
#'   Truncation keeps GBIF's return order -- a non-random prefix -- so both
#'   abundance and spatial pattern become unreliable for capped taxa; prefer
#'   `limit = NULL`, which costs nothing since the records are already
#'   downloaded.
#' @param cache_dir Character or \code{NULL}. Directory for the downloaded
#'   zip file and a small metadata file. Defaults to a persistent user-level
#'   cache directory. Re-running with the same arguments reuses the cached
#'   zip and skips the GBIF download entirely. Set to \code{NULL} to
#'   disable caching.
#' @param overwrite Logical. If \code{FALSE} (default), an existing cached
#'   zip is reused. Set to \code{TRUE} to force a fresh download from GBIF --
#'   in an interactive session this asks for confirmation first (showing the
#'   cached zip's date and size) before deleting it; a non-interactive session
#'   proceeds straight to a fresh download. Either way, the old cached zip is
#'   removed once the new one is saved -- it is never silently orphaned on
#'   disk.
#' @param prompt_mb Numeric. In an INTERACTIVE session, a prepared download at
#'   least this many MB triggers a summary (size, record count, whether a zip
#'   for this exact query is already cached, what the cache holds now and will
#'   hold afterwards) and a choice: use the cache, download and replace it, or
#'   abort to narrow the query first. Smaller downloads proceed silently, and a
#'   NON-interactive session never blocks -- it reports the same facts and
#'   continues. Default \code{50}; \code{Inf} disables the prompt entirely.
#'   The summary is placed before any bytes are transferred, because GBIF
#'   reports a prepared download's size and record count at that point, which
#'   is the only moment the information can still change the decision.
#' @param cache_prompt_mb Numeric. After a run, if the cache directory exceeds
#'   this many MB, an interactive session is offered a choice to free space
#'   (leave it; remove OTHER downloads but keep this query's zip; remove
#'   everything). A non-interactive session only reports. Default \code{5120}
#'   (5 GB); \code{Inf} disables the prompt while keeping the size report.
#' @param keep_zip Logical, default \code{TRUE}. Whether to retain the
#'   downloaded zip in \code{cache_dir} after a successful import. The zip is
#'   pure redundancy once imported -- its only value is avoiding a re-download
#'   -- and it is by far the largest thing this package writes: on one real
#'   machine 38 zips accounted for 17 GB of a 17.05 GB cache, while every
#'   \code{.rds} checkpoint together came to 52 MB. With \code{FALSE} the zip
#'   is deleted after import and the small metadata file is KEPT, so a later
#'   identical call re-fetches the SAME prepared GBIF key -- no new request, no
#'   queue wait, just the transfer. Set \code{FALSE} when the caller persists
#'   the imported data itself (every workflow in this ecosystem saves a
#'   \code{_raw_gbif.rds} checkpoint, which makes the zip doubly redundant).
#'
#' @section Why nothing here blocks by default:
#' On 2026-09-05 a \code{utils::menu()} in this function consumed the ENTIRE
#' remainder of a sourced workflow script as its answers -- roughly 600 lines,
#' each rejected as an invalid selection, each therefore never executed. The
#' GBIF download itself had succeeded; everything after it silently did not
#' run. RStudio queues the rest of a script as pending console input, and
#' \code{menu()}/\code{readline()} read exactly that queue, so
#' \code{interactive()} being \code{TRUE} says nothing about whether a human is
#' waiting to type. This package already documented the same hazard for
#' \code{readline()} in \code{TaxaMatch::group_observations_by_bbox()}, whose
#' advice ("run this call on its own") is unavailable to a function called
#' mid-workflow. Every decision here is therefore REPORTED, with the command to
#' act on it, unless \code{allow_prompts = TRUE} is passed deliberately.
#'
#' @param allow_prompts Logical, default \code{FALSE}. Whether this function may
#'   BLOCK on an interactive \code{utils::menu()}. Off by default because a
#'   blocking prompt inside a function that is called from a script is unsafe:
#'   when RStudio runs or sources a script it queues the remaining lines as
#'   console input, and \code{menu()} consumes those lines as answers --
#'   re-prompting on each one, and, far worse, SILENTLY SWALLOWING them so they
#'   never execute. This package already documents the same hazard for
#'   \code{readline()} in \code{TaxaMatch::group_observations_by_bbox()}; there
#'   the advice is "run this call on its own", which is not available to a
#'   function called mid-workflow. With \code{FALSE} every decision is REPORTED
#'   with the exact command to act on it, and nothing blocks. Set \code{TRUE}
#'   only when calling this function by hand at the console.
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
#' \strong{Cache invalidation:} A cache built by an older version of this
#' function that queried \code{taxonKey} alone (not the OR predicate above)
#' will silently omit records at other ranks. If in doubt, re-run with
#' \code{overwrite = TRUE}.
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
    year_range     = .gbif_default_year_range(),
    limit          = NULL,
    on_cap         = c("warn", "error"),
    cache_dir      = tools::R_user_dir("TaxaFetch", "cache"),
    overwrite      = FALSE,
    prompt_mb      = 50,
    cache_prompt_mb = 5120,
    allow_prompts  = FALSE,
    keep_zip       = TRUE,
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

  on_cap <- match.arg(on_cap)

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
  dl_key         <- NULL
  zip_path       <- NULL
  old_zip_path   <- NULL
  redownload_key <- NULL   # a prepared GBIF key whose local zip was unusable

  if (!is.null(meta_path) && file.exists(meta_path)) {
    meta <- readRDS(meta_path)
    cached_zip_exists <- file.exists(meta$zip_path)

    if (!overwrite) {
      if (cached_zip_exists) {
        # Verify before trusting it. A truncated cached zip used to be reused
        # forever, failing at import on every single run with no hint that the
        # CACHE was the problem (2026-09-04, PtConception 18S).
        .chk <- .gbif_zip_intact(meta$zip_path)
        if (isTRUE(.chk$ok)) {
          dl_key   <- meta$dl_key
          zip_path <- meta$zip_path
          message(sprintf(
            paste0(
              "download_gbif_occurrences: reusing cached zip from %s (key %s).\n",
              "  Set overwrite = TRUE to force a fresh download."
            ),
            format(meta$timestamp, "%Y-%m-%d"), dl_key
          ))
        } else {
          message(sprintf(
            paste0(
              "download_gbif_occurrences: the cached zip is UNUSABLE (%s).\n",
              "  Discarding it and re-fetching download key %s from GBIF -- the key is\n",
              "  already prepared server-side, so this costs no new queue wait."
            ),
            .chk$reason, meta$dl_key
          ))
          file.remove(meta$zip_path)
          redownload_key <- meta$dl_key   # re-fetch THIS key, don't re-request
        }
      } else {
        # The metadata survives a deleted zip on purpose (keep_zip = FALSE, or
        # a manual cache clear), and it carries the download key -- so re-fetch
        # THAT prepared file instead of paying for a fresh request and queue
        # wait. GBIF retains a prepared download for months; if the key has
        # expired the fetch below falls back to a new request.
        redownload_key <- meta$dl_key
        message(sprintf(
          "download_gbif_occurrences: cached zip is gone (%s); re-fetching prepared key %s -- no new request.",
          basename(meta$zip_path), meta$dl_key
        ))
      }
    } else if (cached_zip_exists) {
      # overwrite = TRUE and there's a real cached zip that would otherwise be
      # silently orphaned (repointed away from with no cleanup). Interactively
      # confirm the replacement when possible; a non-interactive session
      # proceeds straight to a fresh download, matching the pre-existing
      # behavior, but the stale zip is still removed once the new one lands
      # (see the cleanup block below) instead of being left as an orphan.
      keep_existing <- FALSE
      # Only ASK when there is a real trade-off. A cached zip that fails the
      # integrity check has nothing to weigh -- replacing it is the only sane
      # move -- so say so and proceed rather than offering "keep the broken
      # file" as a choice.
      old_size_mb <- round(file.info(meta$zip_path)$size / 1024^2, 1)
      .cached_chk <- .gbif_zip_intact(meta$zip_path,
                                      expected_size = .gbif_declared_size(meta$dl_key))
      if (!isTRUE(.cached_chk$ok)) {
        message(sprintf(
          "download_gbif_occurrences: the cached zip is unusable (%s) -- replacing it, no choice to make.",
          .cached_chk$reason))
      } else if (isTRUE(allow_prompts) && interactive()) {
        # The decision needs four facts the old message left out: that the
        # cache is for THIS EXACT query (a hit means every cache-key component
        # matched -- keys, geometry, years, basis, presence-only), that the
        # file is verified complete, what re-downloading actually costs, and
        # which option is normally right. Written after the author of this
        # package hit the old prompt mid-run and could not tell which to pick.
        message(sprintf(paste0(
          "download_gbif_occurrences: a cached zip for THIS EXACT query already exists.\n",
          "  key      : %s\n",
          "  file     : %.1f MB, verified complete (matches GBIF's declared size)\n",
          "  fetched  : %s"),
          meta$dl_key, old_size_mb, format(meta$timestamp, "%Y-%m-%d %H:%M")))
        choice <- utils::menu(
          c(paste0("Re-download -- discard it and fetch again from GBIF ",
                   "(new request + queue wait + ", sprintf("%.1f", old_size_mb),
                   " MB; identical result unless GBIF's data changed since)"),
            "Use the cache -- skip the download and import now  [normally what you want]"),
          title = "This zip is already downloaded and verified. Re-download it?"
        )
        keep_existing <- identical(choice, 2L)
      } else {
        message(sprintf(paste0(
          "download_gbif_occurrences: a verified cached zip for this exact query exists (%.1f MB),\n",
          "  but overwrite = TRUE, so it will be re-downloaded and replaced. To use it instead,\n",
          "  drop overwrite = TRUE (the default reuses it)."), old_size_mb))
      }
      if (keep_existing) {
        dl_key   <- meta$dl_key
        zip_path <- meta$zip_path
        message("download_gbif_occurrences: keeping the existing cached zip.")
      } else {
        old_zip_path <- meta$zip_path
      }
    }
  }

  # --- Submit download if needed ----------------------------------------------
  if (is.null(zip_path)) {
   if (!is.null(redownload_key)) {
    # The query is unchanged and GBIF already prepared this key -- re-fetch the
    # SAME file rather than paying for a fresh request and queue wait.
    dl_key <- redownload_key
    message(sprintf(
      "download_gbif_occurrences: re-fetching prepared download key %s (no new request).",
      dl_key))
   } else {
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
   }

    # Download zip to cache_dir (or tempdir if caching disabled)
    dest_dir <- if (!is.null(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
      cache_dir
    } else {
      tempdir()
    }
    zip_path <- file.path(dest_dir, paste0(dl_key, ".zip"))

    # Consent + cost communication, placed BEFORE any bytes move (GBIF reports
    # size and record count as soon as the download is prepared).
    .prior_zip <- if (!is.null(meta_path) && file.exists(meta_path)) {
      .m <- tryCatch(readRDS(meta_path), error = function(e) NULL)
      if (!is.null(.m) && file.exists(.m$zip_path) &&
          isTRUE(.gbif_zip_intact(.m$zip_path)$ok)) .m$zip_path else NULL
    } else NULL
    .decision <- .gbif_download_consent(dl_key, cache_dir, .prior_zip,
                                        prompt_mb = prompt_mb, keys = keys,
                                        allow_prompts = allow_prompts)
    if (identical(.decision, "abort")) {
      stop("download_gbif_occurrences: aborted before downloading, at your request. ",
           "Narrow the query and re-run -- `geometry` (a smaller polygon), `keys` ",
           "(fewer taxa), `year_range`, or `basis_keep` all shrink it. The prepared ",
           "download stays available on GBIF as key ", dl_key,
           " if you change your mind.", call. = FALSE)
    }
    if (identical(.decision, "use_cache") && !is.null(.prior_zip)) {
      message("download_gbif_occurrences: using the cached zip; no download made.")
      zip_path <- .prior_zip
      old_zip_path <- NULL          # nothing superseded, so nothing to clean up
    } else {
    # Verify EVERY download before it is cached, and retry once. A truncated
    # transfer is precisely the transient failure a retry fixes, and caching an
    # unverified zip is what turned one bad night into a permanent failure
    # (2026-09-04). GBIF's declared size makes the check exact when reachable;
    # the structural test stands alone when it is not.
    .expected <- .gbif_declared_size(dl_key)
    .chk <- list(ok = FALSE, reason = "not attempted")
    for (.attempt in seq_len(2L)) {
      rgbif::occ_download_get(dl_key, path = dest_dir, overwrite = TRUE)
      if (!file.exists(zip_path)) {
        .chk <- list(ok = FALSE, reason = "no file written")
      } else {
        .chk <- .gbif_zip_intact(zip_path, expected_size = .expected)
      }
      if (isTRUE(.chk$ok)) break
      message(sprintf("  Download attempt %d produced an unusable zip (%s).",
                      .attempt, .chk$reason))
      if (file.exists(zip_path)) file.remove(zip_path)
      if (.attempt < 2L) message("  Retrying the same prepared key once...")
    }
    if (!isTRUE(.chk$ok)) {
      stop(sprintf(paste0(
        "download_gbif_occurrences: the GBIF zip for key %s could not be downloaded ",
        "intact after 2 attempts (%s). Nothing was cached, so simply re-running is ",
        "safe -- the key stays prepared server-side. If it keeps failing, check free ",
        "disk space and network stability, or fetch it by hand from\n  %s"),
        dl_key, .chk$reason,
        sprintf("https://api.gbif.org/v1/occurrence/download/request/%s.zip", dl_key)
      ))
    }
    message(sprintf("  Zip saved to: %s (verified%s)", zip_path,
                    if (is.null(.expected)) " structurally"
                    else sprintf(", %s bytes as GBIF declares",
                                 format(.expected, big.mark = ","))))
    }

    # Save metadata -- only ever AFTER verification passes.
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

    if (!is.null(old_zip_path) && file.exists(old_zip_path)) {
      file.remove(old_zip_path)
      message(sprintf("  Removed previous cached zip: %s", old_zip_path))
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

  # ---- Zip retention -------------------------------------------------------
  # Deleted only AFTER a successful import, so a failed import never loses the
  # bytes. The metadata file stays, so the download key remains recoverable and
  # a later identical call re-fetches the same prepared file rather than
  # queueing a new request.
  if (!isTRUE(keep_zip) && !is.null(cache_dir) && file.exists(zip_path)) {
    .zip_mb <- file.info(zip_path)$size / 1024^2
    if (isTRUE(file.remove(zip_path)))
      message(sprintf(
        paste0("  keep_zip = FALSE: removed the %.1f MB zip after import. The download key\n",
               "  (%s) is kept, so an identical re-run re-fetches it without a new request."),
        .zip_mb, dl_key %||% "unknown"))
  }

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
  capped_keys <- integer(0)
  if (!is.null(limit)) {
    if ("taxonKey" %in% names(raw)) {
      counts  <- tapply(seq_len(nrow(raw)), raw$taxonKey, length)
      n_over  <- sum(counts > limit)
      # Truncation is applied HERE, after import -- and what survives is
      # GBIF's own return order, a non-random prefix, NOT a sample. Reported
      # as a warning (not a message) because a silent cap destroys exactly
      # the quantity an occurrence-composition prior is built from: measured
      # 2026-09-02, a limit of 10,000 truncated 45 of Mugu's 231 taxa (95% of
      # the pool) and 110 of PtConception's 666, leaving every capped species
      # with an IDENTICAL spatial distribution because the prefixes came from
      # the same few large survey datasets. `limit = NULL` avoids this
      # entirely and costs nothing -- the records are already downloaded.
      if (n_over > 0L) {
        .cap_msg <- sprintf(
          paste0(
            "download_gbif_occurrences: %d of %d taxon key(s) exceeded limit = %s and were TRUNCATED (%.0f%% of rows). ",
            "Kept records are GBIF's return order, not a random sample, so abundance AND spatial pattern are ",
            "unreliable for those taxa. Pass limit = NULL to keep every record -- they are already downloaded."
          ),
          n_over, length(counts), format(limit),
          100 * sum(counts[counts > limit]) / nrow(raw)
        )
        if (identical(on_cap, "error")) stop(.cap_msg, call. = FALSE)
        warning(.cap_msg, call. = FALSE)
        capped_keys <- as.integer(names(counts)[counts > limit])
      }
      raw <- raw |>
        dplyr::group_by(taxonKey) |>
        dplyr::slice_head(n = limit) |>
        dplyr::ungroup() |>
        as.data.frame()
    } else if (nrow(raw) > limit) {
      warning(sprintf(
        paste0(
          "download_gbif_occurrences: taxonKey column absent; truncating total ",
          "rows to %d (was %d). Per-key limit could not be applied."
        ),
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
  # Construct the GBIF download portal URL directly from the key -- avoids an
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
  attr(raw, "capped_keys") <- capped_keys
  attr(raw, "report_params") <- list(
    source     = "GBIF (async download)",
    n_keys     = length(keys),
    n_records  = nrow(raw),
    doi        = doi_url,
    geometry   = geometry,
    year_range = year_range
  )

  # --- Cache summary / offer to clear ------------------------------------------
  # Wrapped: this block is PURELY COSMETIC -- a size report and an optional
  # housekeeping prompt -- and it runs AFTER the download, the import and the
  # attribute assembly are all complete. Anything that throws in here would
  # discard the entire result, and on 2026-09-05 something did: a package
  # reinstall underneath a running session made a lazy-load read of
  # .taxafetch_cache_patterns fail ("lazy-load database ... is corrupt"), which
  # threw away 1,717,250 successfully imported rows at the last step. A
  # reporting convenience must never be able to lose the data.
  .cache_report <- function() {
  if (!is.null(cache_dir)) {
    inv <- TaxaTools::list_cache_files(cache_dir, .taxafetch_cache_patterns)
    if (nrow(inv) > 0L) {
      total_mb <- sum(inv$size_mb)
      # GB once past a gigabyte: "17123.7 MB" is a number people have to stop
      # and convert before it means anything.
      .gb <- function(mb) if (mb >= 1024) sprintf("%.1f GB", mb / 1024)
                          else sprintf("%.1f MB", mb)
      message(sprintf(
        "download_gbif_occurrences: TaxaFetch cache: %d file(s), %s in %s.",
        nrow(inv), .gb(total_mb), normalizePath(cache_dir, mustWork = FALSE)
      ))
      # This query's own zip is called out separately and offered as a KEEP,
      # because the blanket clear used to include it -- i.e. the prompt that
      # fires right after a download offered to delete the file just
      # downloaded, making an identical re-run pay for it again. Naming its
      # size is also the honest way to show what caching buys.
      this_zip <- if (!is.null(zip_path) && file.exists(zip_path))
        normalizePath(zip_path, mustWork = FALSE) else NA_character_
      this_mb <- if (!is.na(this_zip)) file.info(this_zip)$size / 1024^2 else 0
      other_mb <- max(total_mb - this_mb, 0)
      if (!is.na(this_zip)) {
        message(sprintf(
          "  This query's own zip is %s -- keeping it makes an identical re-run free.",
          .gb(this_mb)))
      }
      if (total_mb > cache_prompt_mb) {
        if (isTRUE(allow_prompts) && interactive()) {
          choice <- utils::menu(
            c("Leave it as it is",
              sprintf("Remove OTHER cached downloads (%s), keep this query's zip", .gb(other_mb)),
              sprintf("Remove everything including this query's zip (%s)", .gb(total_mb))),
            title = sprintf("The TaxaFetch cache is %s. Free some space?", .gb(total_mb)))
          if (identical(choice, 2L)) {
            keep <- if (!is.na(this_zip)) this_zip else character(0)
            gone <- inv$path[normalizePath(inv$path, mustWork = FALSE) != keep]
            removed <- sum(file.remove(gone))
            message(sprintf("  Removed %d file(s); this query's zip kept.", removed))
          } else if (identical(choice, 3L)) {
            taxafetch_clear_cache(cache_dir = cache_dir, dry_run = FALSE)
          }
        } else {
          # Report the same choices as COMMANDS. Never block: a menu here
          # consumes the rest of a sourced script as its answers.
          message(sprintf(paste0(
            "  Over the %s reporting threshold. To free space (nothing is removed automatically):\n",
            "    TaxaFetch::taxafetch_clear_cache(dry_run = TRUE)        # see what is there\n",
            "    TaxaFetch::taxafetch_clear_cache(orphans_only = TRUE)   # superseded files only\n",
            "    TaxaFetch::taxafetch_clear_cache(older_than_days = 30)  # keep recent downloads%s"),
            .gb(cache_prompt_mb),
            if (!is.na(this_zip)) sprintf(
              "\n  This query's zip is %s -- keep it unless you are done with this query.",
              .gb(this_mb)) else ""))
        }
      }
    }
  }
  }
  tryCatch(.cache_report(), error = function(e) {
    warning(sprintf(paste0(
      "download_gbif_occurrences: the cache-size report failed (%s). The ",
      "downloaded data is unaffected and is being returned normally."),
      conditionMessage(e)), call. = FALSE)
  })

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
#' Tell the user what a pending GBIF download will cost, and let them choose
#'
#' Placed where the facts exist: GBIF reports a prepared download's size and
#' record count BEFORE any bytes are transferred, so the decision belongs
#' there rather than after the file has already landed. Communicates, in one
#' place: how big the download is, whether a cached zip for this exact query
#' already exists (and that downloading REPLACES it), what the cache directory
#' currently holds and what it will hold afterwards, and -- when the answer is
#' "that is too much" -- that the real remedy is narrowing the query, naming
#' the arguments that do it.
#'
#' Silent for small downloads (`prompt_mb`) and in any non-interactive session,
#' which must never block: there it reports and proceeds.
#'
#' @return One of "download", "use_cache", "abort".
#' @noRd
.gbif_download_consent <- function(dl_key, cache_dir, cached_zip_path = NULL,
                                   prompt_mb = 50, keys = NULL,
                                   allow_prompts = FALSE) {
  m  <- tryCatch(rgbif::occ_download_meta(dl_key), error = function(e) NULL)
  sz <- suppressWarnings(as.numeric(m$size))
  n_rec <- suppressWarnings(as.numeric(m$totalRecords))
  sz_mb <- if (length(sz) == 1L && isTRUE(is.finite(sz))) sz / 1024^2 else NA_real_

  cache_mb <- NA_real_
  if (!is.null(cache_dir) && dir.exists(cache_dir)) {
    f <- list.files(cache_dir, full.names = TRUE, recursive = TRUE)
    if (length(f)) cache_mb <- sum(file.info(f)$size, na.rm = TRUE) / 1024^2
  }
  .gb <- function(mb) if (!isTRUE(is.finite(mb))) "unknown" else
    if (mb >= 1024) sprintf("%.1f GB", mb / 1024) else sprintf("%.1f MB", mb)

  have_cache <- !is.null(cached_zip_path) && file.exists(cached_zip_path)
  cached_mb  <- if (have_cache) file.info(cached_zip_path)$size / 1024^2 else NA_real_

  lines <- c(
    "download_gbif_occurrences: GBIF has prepared this download.",
    sprintf("  records    : %s", if (isTRUE(is.finite(n_rec)))
              format(n_rec, big.mark = ",") else "unknown"),
    sprintf("  size       : %s%s", .gb(sz_mb),
            if (!is.null(keys)) sprintf("   (%d taxon key(s))", length(keys)) else ""),
    if (!is.null(cache_dir)) sprintf("  cache dir  : %s", cache_dir),
    if (!is.null(cache_dir)) sprintf("  cache now  : %s%s", .gb(cache_mb),
            if (isTRUE(is.finite(cache_mb)) && isTRUE(is.finite(sz_mb)))
              sprintf("  ->  %s after this download",
                      .gb(cache_mb + sz_mb - if (have_cache) cached_mb else 0)) else "")
  )
  if (have_cache) {
    lines <- c(lines,
      sprintf("  cached zip : a zip for THIS EXACT query already exists (%s).", .gb(cached_mb)),
      "               Downloading again REPLACES it; the result is identical",
      "               unless GBIF's data has changed since.")
  } else if (!is.null(cache_dir)) {
    lines <- c(lines,
      "  cached zip : none for this query -- the file is kept so an identical",
      "               re-run costs no download.")
  }
  message(paste(lines[!vapply(lines, is.null, logical(1))], collapse = "\n"))

  # Reaching this point at all means the caller already asked for a download --
  # with overwrite = FALSE a good cached zip is served earlier and never gets
  # here, so a cache present HERE means overwrite = TRUE, an explicit request.
  # Never quietly override that: a non-interactive session (and any download
  # below the prompt threshold) proceeds, and "use the cache" is offered only
  # as an INTERACTIVE second thought. Caught by the pre-existing
  # overwrite = TRUE regression test, not by review.
  too_small <- !isTRUE(is.finite(sz_mb)) || sz_mb < prompt_mb
  if (too_small || !isTRUE(allow_prompts) || !interactive()) {
    if (!too_small && !isTRUE(allow_prompts))
      message(paste0(
        "  Proceeding with the download. To narrow it instead, interrupt and adjust\n",
        "  `geometry` (a smaller polygon), `keys` (fewer taxa), `year_range` or\n",
        "  `basis_keep`. Pass allow_prompts = TRUE to be asked interactively."))
    return("download")
  }

  narrow <- paste0(
    "Abort, to narrow the query first -- geometry (a smaller polygon), ",
    "keys (fewer taxa), year_range, basis_keep")
  opts <- if (have_cache) {
    c(sprintf("Use the cached zip -- no download, import now  [recommended]"),
      sprintf("Download %s and replace the cached zip", .gb(sz_mb)),
      narrow)
  } else {
    c(sprintf("Download %s now  [recommended]", .gb(sz_mb)), narrow)
  }
  choice <- utils::menu(opts, title = "How do you want to proceed?")
  if (have_cache) {
    switch(as.character(choice), "1" = "use_cache", "2" = "download", "abort")
  } else {
    switch(as.character(choice), "1" = "download", "abort")
  }
}

#' Is a downloaded GBIF zip actually complete?
#'
#' A zip's central directory lives at the END of the file, so a download that
#' is cut short leaves a file that still starts with a valid local header (and
#' that `file`/magic-byte checks still call "Zip archive data") but cannot be
#' opened by any reader. Checking only `file.exists()` therefore accepts a
#' truncated download, caches it, and fails on every subsequent import --
#' a self-perpetuating poisoned cache. Found for real on 2026-09-04: a
#' PtConception 18S download landed 127,733,417 of GBIF's declared
#' 130,577,434 bytes, and every re-run printed "Zip cached. Starting import
#' now" and then died in `utils::unzip()`.
#'
#' @param zip_path Character. Path to check.
#' @param expected_size Optional numeric. GBIF's own declared byte size for
#'   this download, when it could be retrieved; `NULL` skips the size test and
#'   relies on the structural one alone (which needs no network).
#' @return List with `ok` (logical) and `reason` (character, `NA` when ok).
#' @noRd
.gbif_zip_intact <- function(zip_path, expected_size = NULL) {
  .bad <- function(r) list(ok = FALSE, reason = r)
  if (is.null(zip_path) || !file.exists(zip_path))
    return(.bad("file does not exist"))
  sz <- file.info(zip_path)$size
  if (!isTRUE(is.finite(sz)) || sz <= 0) return(.bad("file is empty"))
  if (!is.null(expected_size) && isTRUE(is.finite(expected_size)) &&
      expected_size > 0 && !isTRUE(sz == expected_size)) {
    return(.bad(sprintf(
      "size mismatch: %s bytes on disk, GBIF declares %s (short by %s)",
      format(sz, big.mark = ","), format(expected_size, big.mark = ","),
      format(expected_size - sz, big.mark = ","))))
  }
  # Structural test: reading the central directory is exactly what the import
  # step needs to succeed, and it needs no network.
  lst <- tryCatch(utils::unzip(zip_path, list = TRUE),
                  error = function(e) e, warning = function(w) w)
  if (inherits(lst, c("error", "condition")) || !is.data.frame(lst) || nrow(lst) < 1L)
    return(.bad("central directory unreadable -- the file is truncated or corrupt"))
  list(ok = TRUE, reason = NA_character_)
}

#' GBIF's own declared byte size for a download key, or NULL
#' @noRd
.gbif_declared_size <- function(dl_key) {
  m <- tryCatch(rgbif::occ_download_meta(dl_key), error = function(e) NULL)
  sz <- suppressWarnings(as.numeric(m$size))
  if (length(sz) == 1L && isTRUE(is.finite(sz)) && sz > 0) sz else NULL
}

#' @param zip_path Character. Path to the downloaded GBIF zip file.
#' @return A data frame of occurrence records.
#' @noRd
.read_gbif_zip <- function(zip_path, select_cols = NULL) {
  tmp <- tempfile(pattern = "gbif_unzip_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  # Defense-in-depth against zip-slip: zip_path comes from GBIF's own
  # occ_download()/occ_download_get() (a trusted first party), but nothing
  # downstream re-validates that trust (cache tampering, a MITM'd download,
  # etc.), so entry paths are checked before extraction rather than assumed
  # safe.
  entry_names <- utils::unzip(zip_path, list = TRUE)$Name
  unsafe <- entry_names[
    startsWith(entry_names, "/") | grepl("(^|/)\\.\\.(/|$)", entry_names)
  ]
  if (length(unsafe) > 0L) {
    stop(
      "download_gbif_occurrences: refusing to extract '", zip_path,
      "' -- contains unsafe entry path(s) outside the target directory: ",
      paste(unsafe, collapse = ", ")
    )
  }

  # utils::unzip() signals a FAILED extraction (e.g. a CRC mismatch from
  # corruption inside the compressed payload) as a mere WARNING -- "error -3 in
  # extracting from zip file" -- and carries on, which can leave a partially
  # written CSV that then reads as a silently SHORT occurrence table. Since
  # .gbif_zip_intact() deliberately checks only the central directory (cheap, no
  # decompression), this extraction is the step that validates the payload, so
  # its warning is promoted to an error rather than left to a caller who may not
  # be watching. 2026-09-04: added after a truncated download made the failure
  # mode concrete.
  withCallingHandlers(
    utils::unzip(zip_path, exdir = tmp),
    warning = function(w) {
      stop(sprintf(paste0(
        "download_gbif_occurrences: extracting '%s' failed (%s). The archive is ",
        "corrupt, not merely truncated. Delete it and re-run -- the download will ",
        "be re-fetched and verified."), zip_path, conditionMessage(w)),
        call. = FALSE)
    }
  )
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
  if (length(data_file) > 1L) {
    warning(sprintf(
      paste0(
        "download_gbif_occurrences: %d candidate data file(s) found in zip ",
        "at %s -- using the first (%s) and silently ignoring the rest: %s. ",
        "This is unexpected for a standard SIMPLE_CSV download; inspect the ",
        "zip contents if this is not the file you expect."
      ),
      length(data_file), zip_path, basename(data_file[1L]),
      paste(basename(data_file[-1L]), collapse = ", ")
    ), call. = FALSE)
  }
  data_file <- data_file[1L]

  if (requireNamespace("data.table", quietly = TRUE)) {
    # Intersect select_cols with available columns to avoid fread errors on
    # unrecognised names.  Read header-only first (cheap: 0 data rows).
    use_cols <- if (!is.null(select_cols)) {
      available <- names(data.table::fread(data_file, nrows = 0L,
                                           showProgress = FALSE))
      intersect(select_cols, available)
    } else {
      NULL
    }
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
