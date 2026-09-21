# ==============================================================================
# fetch_inat_occurrences.R
# TaxaFetch -- iNaturalist observation-count fetch (captive/casual-grade aware)
#
# Exported functions:
#   fetch_inat_occurrences()   -- local iNaturalist observation count for a
#                                  vector of taxa, with control over quality
#                                  grade and captive/cultivated status
#
# Internal helpers:
#   .inat_observation_count()  -- single-taxon count query against the
#                                  /v1/observations search endpoint
#
# Reuses TaxaFetch:::.inat_taxon_id() (check_inat_range.R) for name resolution
# -- same taxa-search endpoint, no need for a second implementation.
# ==============================================================================

#' Fetch local iNaturalist observation counts, including casual-grade records
#'
#' For each taxon name, resolves the iNaturalist taxon ID and counts
#' observations within a radius of a query point, via iNaturalist's
#' \code{/v1/observations} search endpoint. Unlike \code{\link{check_inat_range}}
#' (which tests a point against a thresholded geomodel range polygon),
#' this function counts real, individual observation records -- including,
#' by default, \code{quality_grade = "casual"} and \code{captive = "any"}
#' records that standard GBIF-style occurrence indexing structurally
#' excludes or under-indexes (captive pets/livestock, cultivated/ornamental
#' plants).
#'
#' @details
#' Intended as a non-GBIF occurrence source for domestic/commensal/food
#' species (see \code{TaxaExpect::generate_domestic_food_priors()}), where
#' GBIF's own occurrence indexing under-counts exactly the organisms this
#' function is meant to detect. Set \code{quality_grade = "research"} and
#' \code{captive = "false"} to reproduce something closer to GBIF-style
#' filtering for comparison.
#'
#' This function counts observations only -- it does not download individual
#' records. The iNaturalist API returns \code{total_results} on every search
#' response regardless of \code{per_page}, so a single lightweight request
#' (\code{per_page = 1}) is sufficient per taxon.
#'
#' \strong{Retry/backoff:} a 429 (rate limit) or 5xx (server error) response
#' from the observation-count request is retried up to 4 attempts total,
#' honouring a server-sent \code{Retry-After} header when present and
#' falling back to a 15/30/60 s backoff otherwise. Once every attempt is
#' exhausted, that taxon's row still gets \code{query_status =
#' "request_failed"} -- retrying only reduces how often a transient
#' rate-limit/outage produces that outcome, it does not change what a
#' persistent failure looks like to the caller.
#'
#' \strong{Omission implements "any":} \code{captive = "any"} and
#' \code{quality_grade = "any"} are implemented by OMITTING the
#' corresponding query parameter from the \code{/v1/observations} request
#' entirely (see \code{.inat_observation_count()}), not by sending an
#' explicit \code{captive=any}/\code{quality_grade=any} value. Verified
#' against the live API (\emph{Turdus migratorius}, \code{per_page = 1}, so
#' only \code{total_results} was compared): both parameters omitted returns
#' \code{total_results = 470344}; adding \code{quality_grade=research}
#' returns \code{434444} (omission is the strict superset, as "any" should
#' be); and sending \code{captive=any} explicitly, with \code{quality_grade}
#' still omitted, also returns \code{470344} -- identical to leaving
#' \code{captive} out altogether. Omitting a parameter and sending it
#' explicitly as \code{"any"} are the same query.
#'
#' @param taxon_names Character vector of species names to check.
#' @param lat Numeric. Latitude of the query point in decimal degrees.
#' @param lng Numeric. Longitude of the query point in decimal degrees.
#' @param radius_km Numeric. Search radius in kilometers. Default 50.
#'   iNaturalist's API caps this at 500.
#' @param captive Character, one of \code{"any"} (default), \code{"true"},
#'   \code{"false"}. Filters on iNaturalist's own captive/cultivated flag --
#'   \code{"true"} isolates exactly the captive/cultivated records GBIF-style
#'   filtering excludes; \code{"any"} includes both.
#' @param quality_grade Character, one of \code{"any"} (default),
#'   \code{"casual"}, \code{"needs_id"}, \code{"research"}. \code{"casual"}
#'   is where iNaturalist routes most captive/cultivated observations, but
#'   is not identical to \code{captive = "true"} -- a wild organism with poor
#'   evidence is also casual grade. Use \code{captive}, not
#'   \code{quality_grade}, to isolate captive/cultivated status specifically.
#' @param api_token Character. iNaturalist API token for taxon name
#'   resolution. Defaults to the \code{INAT_API_TOKEN} environment variable.
#' @param retry_attempts Integer (default \code{4L}). How many times the
#'   observation-count request is attempted in total before giving up when
#'   iNaturalist answers with a 429 (rate limit) or 5xx (server error).
#'   Matches \code{\link{download_gbif_occurrences}}'s
#'   \code{submit_attempts} convention. Any other status (including a
#'   success or a 401) is never retried.
#' @param retry_wait Numeric vector of seconds (default \code{c(15, 30,
#'   60)}) slept between retry attempts when iNaturalist does not send a
#'   \code{Retry-After} header; the last value repeats if
#'   \code{retry_attempts} exceeds its length. A server-sent
#'   \code{Retry-After} value, when present, is honoured instead.
#' @param verbose Logical. If TRUE, prints progress for each taxon. Default FALSE.
#' @return A tibble with columns \code{taxon_name}, \code{taxon_id},
#'   \code{matched_name}, \code{inat_kingdom} (derived from iNaturalist's own
#'   \code{iconic_taxon_name} via the same fixed lookup
#'   \code{\link{check_inat_range}} uses -- compare against your own
#'   candidate's kingdom before trusting a result: iNaturalist resolves names
#'   against its own curated taxonomy, not NCBI's or GBIF's, so a name that
#'   matches an unrelated homonym in a different kingdom is possible, if rare;
#'   a kingdom mismatch is a strong signal to discard the result rather than
#'   act on it), \code{n_observations_local}, \code{query_status}
#'   (\code{"ok"} or \code{"taxon_not_found"}), \code{radius_km},
#'   \code{captive}, \code{quality_grade}.
#' @export
#'
#' @examples
#' \dontrun{
#' # Requires INAT_API_TOKEN in ~/.Renviron
#' fetch_inat_occurrences(
#'   taxon_names = c("Felis catus", "Solanum lycopersicum"),
#'   lat = 34.41,
#'   lng = -119.86,
#'   captive = "any",
#'   quality_grade = "any"
#' )
#' }
fetch_inat_occurrences <- function(
  taxon_names,
  lat,
  lng,
  radius_km = 50,
  captive = c("any", "true", "false"),
  quality_grade = c("any", "casual", "needs_id", "research"),
  api_token = Sys.getenv("INAT_API_TOKEN"),
  retry_attempts = 4L,
  retry_wait = c(15, 30, 60),
  verbose = FALSE
) {
  captive <- match.arg(captive)
  quality_grade <- match.arg(quality_grade)

  if (nchar(api_token) == 0L) {
    stop(
      "INAT_API_TOKEN is not set. ",
      "Add it to ~/.Renviron or call Sys.setenv(INAT_API_TOKEN = 'your_token')."
    )
  }
  if (!is.numeric(lat) || length(lat) != 1L || is.na(lat)) {
    stop("`lat` must be a single non-NA numeric value.")
  }
  if (!is.numeric(lng) || length(lng) != 1L || is.na(lng)) {
    stop("`lng` must be a single non-NA numeric value.")
  }
  if (!is.numeric(radius_km) || length(radius_km) != 1L || is.na(radius_km) || radius_km <= 0) {
    stop("`radius_km` must be a single positive numeric value.")
  }

  results <- vector("list", length(taxon_names))

  for (i in seq_along(taxon_names)) {
    name <- taxon_names[[i]]
    if (verbose) message(sprintf("[%d/%d] %s", i, length(taxon_names), name))

    info <- .inat_taxon_id(name, api_token)
    inat_kingdom <- .iconic_to_kingdom(info$iconic_taxon_name)

    if (is.na(info$taxon_id)) {
      results[[i]] <- tibble::tibble(
        taxon_name            = name,
        taxon_id              = NA_integer_,
        matched_name          = NA_character_,
        inat_kingdom          = NA_character_,
        n_observations_local  = NA_integer_,
        query_status          = "taxon_not_found",
        radius_km             = radius_km,
        captive               = captive,
        quality_grade         = quality_grade
      )
      next
    }

    n_local <- .inat_observation_count(
      taxon_id       = info$taxon_id,
      lat            = lat,
      lng            = lng,
      radius_km      = radius_km,
      captive        = captive,
      quality_grade  = quality_grade,
      api_token      = api_token,
      max_attempts   = retry_attempts,
      waits          = retry_wait
    )

    results[[i]] <- tibble::tibble(
      taxon_name            = name,
      taxon_id              = info$taxon_id,
      matched_name          = info$matched_name,
      inat_kingdom          = inat_kingdom,
      n_observations_local  = n_local,
      query_status          = if (is.na(n_local)) "request_failed" else "ok",
      radius_km             = radius_km,
      captive               = captive,
      quality_grade         = quality_grade
    )
  }

  dplyr::bind_rows(results)
}


# --- Internal helpers ---------------------------------------------------------

#' Count local iNaturalist observations for one resolved taxon ID
#'
#' Retries a 429 (rate limit) or 5xx (server error) response with backoff
#' via `.http_with_retry()` -- see that function for why this is a small,
#' iNaturalist-only helper rather than a reuse of
#' `download_gbif_occurrences.R`'s `.gbif_submit_with_retry()`/
#' `.gbif_wait_with_retry()` engine. A 401 is never retried (raised
#' immediately, same message as before); any other non-200 status, or a
#' network-level failure that survives every retry attempt, returns
#' `NA_integer_` exactly as before -- this only adds retry/backoff ahead of
#' that existing failure path, it does not change what a final failure looks
#' like to the caller (`fetch_inat_occurrences()`'s `query_status` still
#' becomes `"request_failed"`).
#' @noRd
.inat_observation_count <- function(taxon_id, lat, lng, radius_km, captive, quality_grade, api_token,
                                     max_attempts = 4L, waits = c(15, 30, 60)) {
  query <- list(
    taxon_id = taxon_id,
    lat      = lat,
    lng      = lng,
    radius   = radius_km,
    per_page = 1L
  )
  if (captive != "any") query$captive <- captive
  if (quality_grade != "any") query$quality_grade <- quality_grade

  resp <- .http_with_retry(
    function() {
      httr::GET(
        "https://api.inaturalist.org/v1/observations",
        query = query,
        httr::add_headers(Authorization = paste("Bearer", api_token))
      )
    },
    max_attempts = max_attempts,
    waits = waits
  )
  Sys.sleep(0.3)

  if (is.null(resp)) {
    return(NA_integer_)
  }
  if (httr::status_code(resp) == 401L) {
    stop(
      "iNaturalist API returned 401 Unauthorized. ",
      "Your INAT_API_TOKEN may be expired or invalid. ",
      "Generate a new token at https://www.inaturalist.org/users/api_token and ",
      "update it with Sys.setenv(INAT_API_TOKEN = 'new_token') or in ~/.Renviron."
    )
  }
  if (httr::status_code(resp) != 200L) {
    return(NA_integer_)
  }

  parsed <- tryCatch(
    httr::content(resp, as = "parsed", type = "application/json"),
    error = function(e) NULL
  )
  if (is.null(parsed) || is.null(parsed$total_results)) {
    return(NA_integer_)
  }

  as.integer(parsed$total_results)
}

#' Perform an HTTP request with retry/backoff on 429 and 5xx responses
#'
#' A small, self-contained retry engine for a plain `httr::GET()` call,
#' deliberately NOT built on top of `download_gbif_occurrences.R`'s
#' `.gbif_submit_with_retry()`/`.gbif_wait_with_retry()`: those wrap
#' `rgbif::occ_download()`/`occ_download_wait()` and decide whether to retry
#' by pattern-matching GBIF's own error TEXT (`.gbif_transient_error()`,
#' e.g. "Backend fetch failed"), not an httr status code -- there is no
#' contained way to route a status-code-based retry through that engine, and
#' this function does not touch the GBIF download path at all.
#'
#' `request_fn` is called with no arguments and must return an httr response
#' object (a network-level failure, e.g. a curl timeout, is caught and
#' treated as retryable, same as a 429/5xx response). Status 429 or `>= 500`
#' is retried up to `max_attempts` times total, honouring a server-sent
#' `Retry-After` header (seconds) when present, falling back to `waits`
#' (recycling its last value if `max_attempts` exceeds its length)
#' otherwise. Any other status -- including 200 (success) and 401
#' (authentication failure, which callers handle specially and must not
#' have retried) -- is returned immediately without retrying. Once
#' `max_attempts` is exhausted, the last response (or `NULL`, if every
#' attempt failed at the network level) is returned; the caller's existing
#' failure handling takes it from there.
#' @noRd
.http_with_retry <- function(request_fn, max_attempts = 4L, waits = c(15, 30, 60)) {
  last <- NULL
  for (i in seq_len(max_attempts)) {
    resp <- tryCatch(request_fn(), error = function(e) NULL)
    if (!is.null(resp)) {
      status <- httr::status_code(resp)
      if (!(status == 429L || status >= 500L)) {
        return(resp)
      }
    }
    last <- resp
    if (i < max_attempts) {
      Sys.sleep(.http_retry_wait(last, i, waits))
    }
  }
  last
}

#' Seconds to wait before the next retry attempt, honouring Retry-After
#' @noRd
.http_retry_wait <- function(resp, attempt, waits) {
  fallback <- waits[min(attempt, length(waits))]
  if (is.null(resp)) {
    return(fallback)
  }
  retry_after <- tryCatch(httr::headers(resp)[["retry-after"]], error = function(e) NULL)
  if (is.null(retry_after)) {
    return(fallback)
  }
  secs <- suppressWarnings(as.numeric(retry_after))
  if (is.na(secs) || secs < 0) {
    return(fallback)
  }
  secs
}
