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
#'   transient errors (429 or 503), using exponential backoff. Default 4.
#' @param cache_dir Character or \code{NULL}. Directory for checkpoint files.
#'   Defaults to a persistent user-level cache directory
#'   (\code{tools::R_user_dir("TaxaFetch", "cache")}). If a fetch is
#'   interrupted by a transient error, progress is saved as a checkpoint and
#'   re-running with the same arguments resumes from where it stopped. Set to
#'   \code{NULL} to disable checkpointing.
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
#' \strong{When to use this function vs \code{download_gbif_occurrences}:}
#' \itemize{
#'   \item Use \code{fetch_gbif_occurrences} for small exploratory queries
#'     (fewer than roughly 50 keys), when you want immediate per-key progress
#'     feedback, or when you do not have a GBIF account.
#'   \item Use \code{\link{download_gbif_occurrences}} for large taxon lists
#'     (roughly 50 or more keys), when completeness matters (no per-key record
#'     cap), or when this function hits HTTP 429 rate-limit errors. The async
#'     download API processes requests server-side with no per-key rate limits.
#'     A free GBIF account is required.
#' }
#'
#' \strong{Rate limiting and transient errors:} HTTP 429 (rate limit) errors
#' trigger exponential backoff with waits of 30, 60, 120, and 240 seconds per
#' key. HTTP 503 (Service Unavailable) errors are retried with shorter waits
#' (5, 10, 20, 40 seconds). If any key exhausts all retries, the function
#' stops immediately to avoid returning an incomplete, session-inconsistent
#' result. Progress is saved so re-running resumes from the last successful
#' key. To test your connection interactively, run
#' \code{rgbif::occ_data(taxonKey = 1, limit = 1)}.
#' If you see HTTP 429 errors frequently, increase \code{pause_seconds} or
#' reduce \code{chunk_size}, or switch to \code{\link{download_gbif_occurrences}}.
#'
#' \strong{Checkpoint / resume:} Progress is saved after each completed chunk
#' to \code{cache_dir}. The checkpoint file name encodes the call signature
#' (number of keys, key sum, geometry length, year range, limit), so changing
#' any parameter automatically starts a fresh fetch rather than loading a
#' stale checkpoint. To force a fresh fetch with the same parameters, delete
#' the checkpoint file (path is printed when a fetch is interrupted) or set
#' \code{cache_dir = NULL}.
#'
#' \strong{rgbif dependency:} This function requires the \code{rgbif} package,
#' listed under \code{Suggests} rather than \code{Imports} because downstream
#' modeling functions do not require it. Install with
#' \code{install.packages("rgbif")}.
#'
#' @seealso \code{\link{download_gbif_occurrences}} (async alternative for
#'   large queries, no rate limits, requires GBIF account),
#'   \code{\link{make_bbox_wkt}}, \code{\link{get_keys_from_context}},
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
#' # Build a bounding box and fetch (checkpoint saved automatically)
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
                                   cache_dir          = tools::R_user_dir("TaxaFetch", "cache"),
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

  orig_keys <- keys  # full set; preserved for checkpoint signature

  # --- Checkpoint: load if available ------------------------------------------
  prior_records   <- NULL
  checkpoint_path <- .gbif_checkpoint_path(cache_dir, keys, geometry, year_range, limit)

  if (!is.null(checkpoint_path) && file.exists(checkpoint_path)) {
    ckpt   <- readRDS(checkpoint_path)
    n_done <- length(orig_keys) - length(ckpt$remaining_keys)
    message(sprintf(
      "  fetch_gbif_occurrences: resuming from checkpoint -- %d/%d keys already fetched (%d records); %d keys remaining.",
      n_done, length(orig_keys),
      if (is.null(ckpt$partial_records)) 0L else nrow(ckpt$partial_records),
      length(ckpt$remaining_keys)
    ))
    keys          <- ckpt$remaining_keys
    prior_records <- ckpt$partial_records
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
    if (!is.null(chunk_result$records) && nrow(chunk_result$records) > 0L) {
      results[[i]] <- chunk_result$records
    }
    global_pos <- global_pos + length(chunk_keys)

    if (chunk_result$aborted) {
      # Save checkpoint (remaining = keys not yet started, i.e., future chunks)
      if (!is.null(checkpoint_path) && global_pos < length(keys)) {
        remaining <- keys[(global_pos + 1L):length(keys)]
        saveRDS(list(
          partial_records = dplyr::bind_rows(c(list(prior_records),
                                               results[seq_len(i)])),
          remaining_keys  = remaining,
          keys_total      = orig_keys,
          timestamp       = Sys.time()
        ), checkpoint_path)
        stop(sprintf(
          "fetch_gbif_occurrences: fetch aborted after %d/%d keys.\n  Progress saved -- re-run with the same arguments to resume.\n  To start fresh instead, delete: %s",
          global_pos, length(orig_keys), checkpoint_path
        ), call. = FALSE)
      } else {
        stop(
          "fetch_gbif_occurrences: fetch aborted early.\n",
          "  Enable cache_dir for resumable fetches.",
          call. = FALSE
        )
      }
    }

    # Save checkpoint after each completed chunk (so future abort can resume
    # from here). Signature is baked into the filename -- changed parameters
    # produce a different path and start fresh automatically.
    if (!is.null(checkpoint_path) && global_pos < length(keys)) {
      remaining <- keys[(global_pos + 1L):length(keys)]
      saveRDS(list(
        partial_records = dplyr::bind_rows(c(list(prior_records),
                                             results[seq_len(i)])),
        remaining_keys  = remaining,
        keys_total      = orig_keys,
        timestamp       = Sys.time()
      ), checkpoint_path)
    }

    if (i < n_chunks) Sys.sleep(pause_seconds)
  }

  # --- Combine all records (prior + this run) ---------------------------------
  out <- dplyr::bind_rows(c(list(prior_records), results))

  # Clean up checkpoint on successful completion
  if (!is.null(checkpoint_path) && file.exists(checkpoint_path)) {
    file.remove(checkpoint_path)
  }

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
    nrow(out), length(orig_keys)
  ))

  # --- Attach report_params for report_fetch() --------------------------------
  rp <- list(
    source    = "GBIF",
    n_keys    = length(orig_keys),
    n_records = nrow(out)
  )
  if (!is.null(geometry)   && nzchar(geometry))   rp$geometry   <- geometry
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
# Internal helpers
# ==============================================================================

#' Build the checkpoint file path for a given call signature
#'
#' The filename encodes key count, key sum, geometry length, year range, and
#' limit. Changing any parameter produces a different filename, so mismatched
#' checkpoints from previous runs are automatically ignored.
#'
#' @param cache_dir Character or NULL.
#' @param keys Integer vector (already deduped and NA-free).
#' @param geometry WKT string.
#' @param year_range Character year range.
#' @param limit Integer per-key record limit.
#' @return A file path string, or \code{NULL} if \code{cache_dir} is NULL.
#' @noRd

.gbif_checkpoint_path <- function(cache_dir, keys, geometry, year_range, limit) {
  if (is.null(cache_dir)) return(NULL)
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  sig <- sprintf(
    "%dk_s%d_g%d_%s_l%d",
    length(keys),
    as.integer(sum(as.numeric(keys)) %% 1e9),
    nchar(geometry),
    gsub("[^0-9]", "", year_range),
    as.integer(limit)
  )
  file.path(cache_dir, paste0("gbif_fetch_", sig, ".rds"))
}


#' Fetch one chunk of taxon keys from GBIF
#'
#' Loops over keys in a single chunk, calls \code{rgbif::occ_data} for each,
#' validates that the query key appears in the returned record's taxonomic
#' hierarchy, and returns the combined results for the chunk.
#'
#' @param keys_chunk Integer vector of keys for this chunk.
#' @param geometry WKT string.
#' @param year_range Character year range e.g. \code{"2000,2024"}.
#' @param limit Integer per-key record limit.
#' @param global_pos Integer. Offset into the full key list for progress
#'   reporting.
#' @param total Integer. Total number of keys across all chunks.
#' @return A named list: \code{$records} (data frame or NULL) and
#'   \code{$aborted} (logical). When \code{aborted} is TRUE, the outer
#'   function saves a checkpoint and stops.
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

  should_abort    <- FALSE
  per_key_results <- vector("list", length(keys_chunk))

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
        # All retries exhausted. Never silently skip a key — that would
        # produce session-inconsistent results. Signal abort to outer loop.
        is_503 <- .is_service_unavailable(resp)
        is_429 <- .is_rate_limit(resp)
        reason <- if (is_503)
          "HTTP 503 (GBIF service unavailable) persisted after all retries."
        else if (is_429)
          paste0("HTTP 429 (rate limit) persisted after all retries.",
                 " Re-run later or increase pause_seconds.")
        else
          sprintf("key %d failed after all retries -- %s",
                  key, conditionMessage(resp))
        warning(sprintf(
          "fetch_gbif_occurrences: key %d failed -- %s",
          key, conditionMessage(resp)), call. = FALSE)
        message(
          "\n  fetch_gbif_occurrences: ", reason,
          "\n  To diagnose, run: rgbif::occ_data(taxonKey = 1, limit = 1)",
          "\n  If that fails, check your internet connection or GBIF service status at gbif.org."
        )
        should_abort <- TRUE
        resp <- NULL
        break
      }
    }

    if (should_abort) break
    if (is.null(resp) || inherits(resp, "error")) next

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

  records <- dplyr::bind_rows(per_key_results)
  list(
    records = if (nrow(records) == 0L) NULL else records,
    aborted = should_abort
  )
}
