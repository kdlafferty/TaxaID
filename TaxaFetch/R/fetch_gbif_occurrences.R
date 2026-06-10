# ==============================================================================
# fetch_gbif_occurrences.R
# TaxaExpect -- Download GBIF occurrence records for a set of taxon keys
# ==============================================================================

#' Fetch GBIF Occurrence Records for a Set of Taxon Keys
#'
#' Downloads occurrence records from GBIF for a vector of taxon usage keys,
#' processing them in chunks to stay within API rate limits. Returns a single
#' combined tibble of all records that pass hierarchy validation.
#'
#' @param keys Integer or numeric vector. GBIF taxon usage keys. Typically the
#'   output of \code{\link{get_keys_from_context}} or
#'   \code{rgbif::name_backbone()}. Duplicates are removed before processing.
#' @param geometry Character. A WKT polygon string defining the geographic
#'   search area. Use \code{\link{make_bbox_wkt}} to generate from a centre
#'   lat/lon and radius.
#' @param year_range Character. Year range for the GBIF query, formatted as
#'   \code{"YYYY,YYYY"}, e.g. \code{"2000,2024"}. Passed directly to
#'   \code{rgbif::occ_data(year = ...)}.
#' @param limit Integer. Maximum records to return per taxon key. GBIF caps
#'   this at 100,000; default 10,000 is usually sufficient for regional
#'   queries.
#' @param chunk_size Integer. Number of keys per API batch. Default 20.
#'   Reduce if you experience HTTP 429 rate-limit errors; increase cautiously.
#' @param pause_seconds Numeric. Seconds to pause between chunks. Default 2.
#'   Increase to be polite to the API under heavy load.
#' @param pause_between_keys Numeric. Seconds to pause between individual key
#'   requests within a chunk. Default 0.5. Increase if 429 errors persist.
#' @param max_retries Integer. Maximum number of retry attempts per key on
#'   rate-limit (429) errors, using exponential backoff starting at 30 seconds.
#'   Default 4 (waits up to ~4 minutes total per key before giving up).
#' @param beep Logical. If \code{TRUE} and the \code{beepr} package is
#'   available, plays a sound on completion. Falls back to a system bell
#'   character if \code{beepr} is absent. Default \code{FALSE}.
#'
#' @return A tibble of occurrence records with GBIF's standard columns.
#'   Only records where the query key appears somewhere in the returned
#'   record's taxonomic hierarchy are retained (see Details). Returns an
#'   empty tibble with a warning if no records pass.
#'
#' @details
#' \strong{Hierarchy validation:} GBIF sometimes returns records for synonyms
#' or higher-rank ancestors of the queried key. Each returned record is
#' checked to confirm that the query key appears somewhere in its taxonomic
#' hierarchy columns (\code{taxonKey}, \code{speciesKey}, \code{genusKey},
#' \code{familyKey}, \code{orderKey}, \code{classKey}, \code{phylumKey},
#' \code{kingdomKey}, \code{acceptedTaxonKey}). Records that fail this check
#' are silently dropped. This prevents off-target taxa from entering the
#' dataset when searching at family or order level.
#'
#' \strong{Rate limiting and transient errors:} GBIF's occurrence API allows
#' roughly 100 requests per minute for authenticated users and fewer for
#' anonymous requests. HTTP 429 (rate limit) errors trigger exponential backoff
#' with waits of 30, 60, 120, and 240 seconds per key before giving up.
#' HTTP 503 (Service Unavailable) errors are also retried automatically with
#' shorter waits (5, 10, 20, 40 seconds). If three or more consecutive keys
#' fail after all retries, the function stops early and prints a connectivity
#' diagnostic message. To test your connection interactively, run
#' \code{rgbif::occ_data(taxonKey = 1, limit = 1)}.
#' If you see HTTP 429 errors frequently, increase \code{pause_seconds} or
#' reduce \code{chunk_size}.
#'
#' \strong{rgbif dependency:} This function requires the \code{rgbif} package,
#' listed under \code{Suggests} rather than \code{Imports} because downstream
#' modeling functions do not require it. Install with
#' \code{install.packages("rgbif")}.
#'
#' @seealso \code{\link{make_bbox_wkt}}, \code{\link{get_keys_from_context}},
#'   \code{\link{filter_gbif_quality}}, \code{\link{stack_occurrences}}
#'
#' @importFrom dplyr bind_rows tibble
#' @export
#'
#' @examples
#' \dontrun{
#' # Resolve keys first
#' taxa_df <- data.frame(
#'   family  = "Gadidae",
#'   species = "Gadus morhua",
#'   stringsAsFactors = FALSE
#' )
#' keys_df <- get_keys_from_context(taxa_df)
#' valid_keys <- keys_df$usageKey[!is.na(keys_df$usageKey)]
#'
#' # Build a bounding box and fetch
#' bbox <- make_bbox_wkt(lat = 56.0, lon = 4.0, radius_deg = 2.0)
#' occ  <- fetch_gbif_occurrences(
#'   keys       = valid_keys,
#'   geometry   = bbox,
#'   year_range = "2010,2024",
#'   limit      = 10000L
#' )
#'
#' # Quality-filter and continue pipeline
#' occ_clean <- filter_gbif_quality(occ)
#' }

fetch_gbif_occurrences <- function(keys,
                                   geometry,
                                   year_range         = "2000,2024",
                                   limit              = 10000L,
                                   chunk_size         = 20L,
                                   pause_seconds      = 2,
                                   pause_between_keys = 0.5,
                                   max_retries        = 4L,
                                   beep               = FALSE) {

  # --- Dependency check -------------------------------------------------------
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop(
      "fetch_gbif_occurrences: package 'rgbif' is required for GBIF downloads.\n",
      "Install it with: install.packages('rgbif')"
    )
  }

  # --- Input checks -----------------------------------------------------------
  keys <- unique(as.integer(keys))
  keys <- keys[!is.na(keys)]

  if (length(keys) == 0L) {
    stop("fetch_gbif_occurrences: 'keys' is empty after removing NAs.")
  }
  if (!is.character(geometry) || length(geometry) != 1L) {
    stop("fetch_gbif_occurrences: 'geometry' must be a single WKT string.")
  }

  total    <- length(keys)
  chunks   <- split(keys, ceiling(seq_along(keys) / chunk_size))
  n_chunks <- length(chunks)

  message(sprintf(
    "fetch_gbif_occurrences: fetching %d key(s) in %d chunk(s) of up to %d...",
    total, n_chunks, chunk_size
  ))

  # --- Fetch chunks -----------------------------------------------------------
  results    <- vector("list", n_chunks)
  global_pos <- 0L

  for (i in seq_along(chunks)) {
    chunk_keys   <- chunks[[i]]
    chunk_result <- .fetch_chunk(
      keys_chunk         = chunk_keys,
      geometry           = geometry,
      year_range         = year_range,
      limit              = limit,
      global_pos         = global_pos,
      total              = total,
      pause_between_keys = pause_between_keys,
      max_retries        = max_retries
    )
    if (!is.null(chunk_result) && nrow(chunk_result) > 0L) {
      results[[i]] <- chunk_result
    }
    global_pos <- global_pos + length(chunk_keys)
    if (i < n_chunks) Sys.sleep(pause_seconds)
  }

  # --- Combine ----------------------------------------------------------------
  out <- dplyr::bind_rows(results)

  if (nrow(out) == 0L) {
    warning(
      "fetch_gbif_occurrences: no records returned for any key. ",
      "Check that keys are valid and the geometry intersects known records.",
      call. = FALSE
    )
    return(dplyr::tibble())
  }

  # --- Add bibliographic citation ---------------------------------------------
  if (!"bibliographicCitation" %in% names(out))
    out$bibliographicCitation <- "GBIF.org. GBIF Occurrence Download via rgbif"

  message(sprintf(
    "fetch_gbif_occurrences: %d records retrieved across %d key(s).",
    nrow(out), total
  ))

  # --- Attach report_params for report_fetch() --------------------------------
  rp <- list(
    source = "GBIF",
    n_keys = total,
    n_records = nrow(out)
  )
  if (!is.null(geometry) && nzchar(geometry)) rp$geometry <- geometry
  if (!is.null(year_range) && nzchar(year_range)) rp$year_range <- year_range
  attr(out, "report_params") <- rp

  # --- Optional completion beep -----------------------------------------------
  if (beep) {
    if (requireNamespace("beepr", quietly = TRUE)) {
      beepr::beep(sound = 2)
    } else {
      cat("\007")
    }
  }

  out
}


# ==============================================================================
# Internal helper
# ==============================================================================

#' Fetch one chunk of taxon keys from GBIF
#'
#' Loops over keys in a single chunk, calls \code{rgbif::occ_data} for each,
#' validates that the query key appears in the returned record's taxonomic
#' hierarchy, and returns the combined dataframe for the chunk.
#'
#' @param keys_chunk Integer vector of keys for this chunk.
#' @param geometry WKT string.
#' @param year_range Character year range e.g. \code{"2000,2024"}.
#' @param limit Integer per-key record limit.
#' @param global_pos Integer. Offset into the full key list for progress
#'   reporting.
#' @param total Integer. Total number of keys across all chunks.
#' @return A data frame (possibly empty) of records for this chunk, or
#'   \code{NULL} if all keys failed.
#' @noRd

.fetch_chunk <- function(keys_chunk, geometry, year_range, limit,
                         global_pos, total,
                         pause_between_keys = 0.5,
                         max_retries        = 4L) {

  hierarchy_cols <- c("taxonKey", "speciesKey", "genusKey", "familyKey",
                      "orderKey",  "classKey",   "phylumKey", "kingdomKey",
                      "acceptedTaxonKey")

  # 429 = rate limit: longer waits (30, 60, 120, 240 sec)
  .is_rate_limit <- function(e) {
    grepl("429|Too many requests|rate.limit", conditionMessage(e),
          ignore.case = TRUE)
  }

  # 503 = server temporarily unavailable: shorter waits (5, 10, 20, 40 sec)
  .is_service_unavailable <- function(e) {
    grepl("503|Service Unavailable", conditionMessage(e),
          ignore.case = TRUE)
  }

  .fetch_one_key <- function(key) {
    rgbif::occ_data(
      taxonKey      = key,
      geometry      = geometry,
      year          = year_range,
      limit         = limit,
      hasCoordinate = TRUE
    )
  }

  consecutive_failures <- 0L
  per_key_results      <- vector("list", length(keys_chunk))

  for (i in seq_along(keys_chunk)) {

    key <- keys_chunk[[i]]
    pos <- global_pos + i
    if (i > 1L) Sys.sleep(pause_between_keys)
    message(sprintf("  [%d / %d] key %d", pos, total, key))

    resp    <- NULL
    attempt <- 0L
    repeat {
      resp <- tryCatch(.fetch_one_key(key), error = function(e) e)
      if (!inherits(resp, "error")) break
      attempt <- attempt + 1L
      if (.is_rate_limit(resp) && attempt <= max_retries) {
        wait <- 30 * 2^(attempt - 1L)   # 30, 60, 120, 240 sec
        message(sprintf(
          "  Rate limit (429) for key %d (attempt %d/%d). Waiting %d sec...",
          key, attempt, max_retries, wait))
        Sys.sleep(wait)
      } else if (.is_service_unavailable(resp) && attempt <= max_retries) {
        wait <- 5 * 2^(attempt - 1L)    # 5, 10, 20, 40 sec
        message(sprintf(
          "  GBIF service unavailable (503) for key %d (attempt %d/%d). Waiting %d sec...",
          key, attempt, max_retries, wait))
        Sys.sleep(wait)
      } else {
        warning(sprintf(
          "fetch_gbif_occurrences: key %d failed -- %s", key,
          conditionMessage(resp)), call. = FALSE)
        consecutive_failures <- consecutive_failures + 1L
        if (consecutive_failures >= 3L) {
          message(
            "\n  fetch_gbif_occurrences: ", consecutive_failures,
            " consecutive key failures -- this looks like a connectivity or",
            "\n  GBIF availability issue, not a per-key problem.",
            "\n  Stopping early to avoid further wasted requests.",
            "\n",
            "\n  To diagnose, run this interactively:",
            "\n    rgbif::occ_data(taxonKey = 1, limit = 1)",
            "\n  If that also fails, check your internet connection.",
            "\n  You can also check GBIF service status at gbif.org."
          )
          break
        }
        resp <- NULL  # mark as failed; skip to next key
        break
      }
    }

    if (is.null(resp) || inherits(resp, "error")) next

    consecutive_failures <- 0L  # reset on success

    df <- resp$data
    if (is.null(df) || nrow(df) == 0L) next

    # Hierarchy validation: confirm the query key appears somewhere in the
    # returned record's taxonomic lineage. Drops off-target synonyms.
    present_cols <- intersect(hierarchy_cols, names(df))
    if (length(present_cols) == 0L) {
      per_key_results[[i]] <- df
      next
    }

    m <- as.matrix(df[present_cols])
    storage.mode(m) <- "integer"
    key_found <- rowSums(m == key, na.rm = TRUE) > 0L
    per_key_results[[i]] <- df[key_found, , drop = FALSE]
  }

  result <- dplyr::bind_rows(per_key_results)
  if (nrow(result) == 0L) NULL else result
}
