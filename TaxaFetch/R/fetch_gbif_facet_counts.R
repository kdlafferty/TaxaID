# ==============================================================================
# fetch_gbif_facet_counts.R
# TaxaFetch -- Species-level GBIF record COUNTS in distance bands around a site
# ==============================================================================

#' Fetch species-level GBIF record counts in distance bands around a site
#'
#' The count-only counterpart of [download_gbif_occurrences()]: same taxon
#' keys, same search polygon, same year filter -- but instead of downloading
#' every record it asks GBIF's occurrence-search API for per-species record
#' COUNTS (`limit = 0`, `facet = speciesKey`) inside a set of concentric
#' distance bands around one site. The result feeds
#' `TaxaExpect::estimate_facet_priors()`, which returns the same prior object
#' [TaxaExpect::estimate_kernel_priors()] does.
#'
#' Cost is set by the number of bands and key batches, not by the number of
#' records: every band is one request per batch of `key_batch_size` taxon
#' keys, however many millions of records fall inside it. The one cost that
#' does grow with the pool is naming it -- GBIF facets return species KEYS,
#' so each distinct species key is looked up once
#' (`/v1/species/{key}`) and kept in `cache_dir` for every later call.
#'
#' @section What the counts do and don't carry:
#' Only records resolved to species level are counted (the facet counts
#' records by `speciesKey`), which is also what the kernel path keeps after
#' `filter_gbif_quality(require_species = TRUE)`. The server-side filters are
#' `occurrenceStatus = PRESENT`, `hasCoordinate = TRUE`,
#' `hasGeospatialIssue = FALSE`, plus `year_range`/`basis_of_record`. The
#' record-level screens in [filter_gbif_quality()] (coordinate precision,
#' coordinate uncertainty, institution proximity) and every per-record step
#' downstream of it (habitat assignment by location, spatial review, a depth
#' covariate) have no count-only equivalent and are not applied.
#'
#' @section Bands:
#' Band `k` holds the records whose distance to the site lies in
#' `(breaks_km[k-1], breaks_km[k]]`, obtained by differencing cumulative
#' `geoDistance` counts. When `geometry` is supplied every band is ALSO
#' clipped to it (GBIF combines the two filters with AND), and one extra
#' band (`band_hi_km = Inf`) holds the rest of the polygon beyond the last
#' break -- so summed over bands, each species' count equals its count in
#' the polygon, which is the pool the kernel path's regional back-off uses.
#' Default breaks, given `lambda_km`: `lambda_km * c(0.25, 0.5, 1, 1.5, 2,
#' 3, 4, 6, 9)`. They include `3 * lambda_km`, the kernel's default
#' neighborhood-support radius (`support_weight = exp(-3)`), so singleton
#' and doubleton counts are exact at that radius, and `6 * lambda_km`, the
#' kernel's fetch-radius check.
#'
#' @param keys Numeric vector of GBIF backbone taxon keys defining the taxonomic
#'   scope -- the same keys you would pass to [download_gbif_occurrences()]
#'   (typically from [get_keys_from_context()]). Any rank; a record counts
#'   when any of its lineage keys matches.
#' @param site_lat,site_lon Numeric scalars. Band centre.
#' @param geometry Character WKT polygon or `NULL`. The search polygon (the
#'   same one the occurrence fetch uses); anticlockwise ring, as GBIF
#'   requires. `NULL`: bands only, no regional remainder band.
#' @param lambda_km Numeric or `NULL`. Kernel bandwidth the counts will be
#'   used with; sets the default `breaks_km`. One of `lambda_km` /
#'   `breaks_km` is required.
#' @param breaks_km Numeric vector or `NULL`. Increasing band outer edges, in
#'   km. Overrides the `lambda_km` default.
#' @param year_range Character `"YYYY,YYYY"` or `NULL` (no year filter).
#'   Default: 2000 through the current year, as in [fetch_gbif_occurrences()].
#' @param basis_of_record Character vector or `NULL` (no filter), e.g.
#'   `c("HUMAN_OBSERVATION", "PRESERVED_SPECIMEN")`.
#' @param key_batch_size Integer. Taxon keys per request (keys are OR-ed
#'   within a request; batches are disjoint and summed). Default 150 keeps
#'   URLs well under GBIF's limit.
#' @param resolve_names Logical. Look up each species key's name and
#'   classification (default `TRUE`). `FALSE` returns keys only.
#' @param cache_dir Character or `NULL`. Persistent cache for both the band
#'   counts (keyed by a hash of every argument that changes the answer) and
#'   the per-species-key classification. `NULL` disables caching.
#' @param max_active Integer. Concurrent requests. Default 4.
#' @param base_url Character. GBIF API root. Exposed for testing.
#'
#' @return A tibble with one row per species x band holding records:
#'   `taxon_name` (GBIF canonical species name), `speciesKey`, `kingdom`,
#'   `phylum`, `class`, `order`, `family`, `genus`, `band`, `band_lo_km`,
#'   `band_hi_km`, `n`. Attributes: `query` (the arguments), `n_requests`,
#'   `n_species_lookups` (uncached classification lookups made by this
#'   call), `total_records` (all species-level records counted), `timing`
#'   (seconds), `fetched_at`.
#' @seealso `TaxaExpect::estimate_facet_priors()`, [estimate_gbif_fetch_cost()]
#'   to choose between this and [download_gbif_occurrences()].
#' @export
#' @examples
#' \dontrun{
#' counts <- fetch_gbif_facet_counts(valid_keys, 34.4, -120.4,
#'   geometry = bbox, lambda_km = 25, year_range = "1995,2026"
#' )
#' }
fetch_gbif_facet_counts <- function(keys,
                                    site_lat,
                                    site_lon,
                                    geometry = NULL,
                                    lambda_km = NULL,
                                    breaks_km = NULL,
                                    year_range = .gbif_default_year_range(),
                                    basis_of_record = NULL,
                                    key_batch_size = 150L,
                                    resolve_names = TRUE,
                                    cache_dir = tools::R_user_dir("TaxaFetch", "cache"),
                                    max_active = 4L,
                                    base_url = "https://api.gbif.org/v1") {
  keys <- sort(unique(stats::na.omit(as.numeric(keys))))
  if (!length(keys)) stop("fetch_gbif_facet_counts: `keys` is empty.")
  for (nm in c("site_lat", "site_lon")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v)) {
      stop(sprintf("fetch_gbif_facet_counts: `%s` must be a single number.", nm))
    }
  }
  if (is.null(breaks_km)) {
    if (is.null(lambda_km)) {
      stop("fetch_gbif_facet_counts: supply `lambda_km` (sets default bands) or `breaks_km`.")
    }
    breaks_km <- lambda_km * c(0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 9)
  }
  if (!is.numeric(breaks_km) || any(!is.finite(breaks_km)) || any(breaks_km <= 0) ||
    is.unsorted(breaks_km, strictly = TRUE)) {
    stop("fetch_gbif_facet_counts: `breaks_km` must be positive, finite and strictly increasing.")
  }

  query <- list(
    keys = keys, site_lat = site_lat, site_lon = site_lon, geometry = geometry,
    breaks_km = breaks_km, year_range = year_range,
    basis_of_record = sort(basis_of_record), base_url = base_url
  )
  cache_path <- NULL
  if (!is.null(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    cache_path <- file.path(cache_dir, paste0("gbif_facet_", rlang::hash(query), ".rds"))
    if (file.exists(cache_path)) {
      hit <- tryCatch(readRDS(cache_path), error = function(e) NULL)
      if (!is.null(hit) && identical(attr(hit, "query"), query)) {
        message(sprintf(
          "fetch_gbif_facet_counts: cached band counts from %s (clear %s to refetch).",
          format(attr(hit, "fetched_at")), basename(cache_path)
        ))
        return(hit)
      }
    }
  }

  t0 <- Sys.time()
  filt <- paste0(
    "limit=0&occurrenceStatus=PRESENT&hasCoordinate=true&hasGeospatialIssue=false",
    "&facet=speciesKey&facetLimit=", .facet_limit,
    if (!is.null(year_range)) paste0("&year=", year_range) else "",
    if (length(basis_of_record)) paste0("&basisOfRecord=", basis_of_record, collapse = "") else ""
  )
  geo <- if (is.null(geometry)) "" else paste0("&geometry=", utils::URLencode(geometry, reserved = TRUE))
  batches <- split(keys, ceiling(seq_along(keys) / key_batch_size))
  spec <- expand.grid(
    edge = c(breaks_km, if (!is.null(geometry)) Inf), batch = seq_along(batches),
    KEEP.OUT.ATTRS = FALSE
  )
  urls <- vapply(seq_len(nrow(spec)), function(i) {
    e <- spec$edge[i]
    ring <- if (is.finite(e)) sprintf("&geoDistance=%s,%s,%skm", site_lat, site_lon, format(e, scientific = FALSE, trim = TRUE)) else ""
    paste0(
      base_url, "/occurrence/search?", filt, geo, ring,
      paste0("&taxonKey=", format(batches[[spec$batch[i]]], scientific = FALSE, trim = TRUE), collapse = "")
    )
  }, character(1))
  res <- .gbif_get_json_parallel(urls, max_active)

  cum <- do.call(rbind, lapply(seq_along(res), function(i) {
    fc <- res[[i]]$facets
    cnt <- if (length(fc)) fc[[1L]]$counts else list()
    if (length(cnt) >= .facet_limit) {
      stop(sprintf(
        "fetch_gbif_facet_counts: a request returned %d species, the facet limit -- the list may be truncated. Lower key_batch_size.",
        length(cnt)
      ))
    }
    if (!length(cnt)) return(NULL)
    data.frame(
      speciesKey = vapply(cnt, function(z) as.character(z$name), character(1)),
      cum_n = vapply(cnt, function(z) as.numeric(z$count), numeric(1)),
      edge = spec$edge[i], stringsAsFactors = FALSE
    )
  }))
  if (is.null(cum)) {
    stop("fetch_gbif_facet_counts: GBIF returned no species-level records for these keys and area.")
  }
  # Batches are disjoint key sets, so a species' cumulative count is the sum.
  cum <- stats::aggregate(cum_n ~ speciesKey + edge, data = cum, FUN = sum)
  edges <- sort(unique(spec$edge))
  wide <- stats::xtabs(cum_n ~ speciesKey + factor(edge, levels = edges), data = cum)
  wide <- matrix(as.numeric(wide), nrow = nrow(wide), dimnames = list(rownames(wide), NULL))
  # Cumulative -> per-band by differencing. The polygon column is a superset
  # of every clipped ring, so differences are non-negative; pmax() only
  # absorbs index-refresh jitter between requests.
  band_n <- wide - cbind(0, wide[, -ncol(wide), drop = FALSE])
  band_n <- pmax(band_n, 0)
  lo <- c(0, edges[-length(edges)])
  out <- data.frame(
    speciesKey = rep(rownames(wide), times = ncol(wide)),
    band = rep(seq_along(edges), each = nrow(wide)),
    band_lo_km = rep(lo, each = nrow(wide)),
    band_hi_km = rep(edges, each = nrow(wide)),
    n = as.numeric(band_n), stringsAsFactors = FALSE
  )
  out <- out[out$n > 0, , drop = FALSE]

  n_lookups <- 0L
  if (resolve_names) {
    cls <- .gbif_species_classification(unique(out$speciesKey), cache_dir, max_active, base_url)
    n_lookups <- attr(cls, "n_fetched")
    out <- merge(cls, out, by = "speciesKey", all.y = TRUE, sort = FALSE)
  }
  out <- tibble::as_tibble(out[order(out$speciesKey, out$band), , drop = FALSE])
  front <- intersect(c("taxon_name", "speciesKey", "kingdom", "phylum", "class", "order", "family", "genus"), names(out))
  out <- out[, c(front, setdiff(names(out), front))]

  attr(out, "query") <- query
  attr(out, "n_requests") <- length(urls) + n_lookups
  attr(out, "n_species_lookups") <- n_lookups
  attr(out, "total_records") <- sum(out$n)
  attr(out, "timing") <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  attr(out, "fetched_at") <- Sys.time()
  if (!is.null(cache_path)) saveRDS(out, cache_path)
  message(sprintf(
    "fetch_gbif_facet_counts: %d species, %s species-level records, %d bands, %d requests (%d name lookups) in %.1f s.",
    length(unique(out$speciesKey)), format(sum(out$n), big.mark = ","), length(edges),
    attr(out, "n_requests"), n_lookups, attr(out, "timing")
  ))
  out
}

# Facet page size. A request returning this many species may be truncated, so
# fetch_gbif_facet_counts() stops rather than silently under-counting.
.facet_limit <- 200000L

#' Parallel GET of GBIF JSON with retry (429/5xx back off inside httr2)
#' @noRd
.gbif_get_json_parallel <- function(urls, max_active = 4L) {
  reqs <- lapply(urls, function(u) {
    httr2::request(u) |>
      httr2::req_retry(max_tries = 6) |>
      httr2::req_timeout(180)
  })
  resps <- httr2::req_perform_parallel(reqs, max_active = max_active, on_error = "continue", progress = FALSE)
  lapply(seq_along(resps), function(i) {
    r <- resps[[i]]
    if (!inherits(r, "httr2_response")) {
      stop(sprintf("GBIF request failed (%s): %s", conditionMessage(r), substr(urls[i], 1, 200)))
    }
    httr2::resp_body_json(r)
  })
}

#' Name + classification for GBIF species keys, cached per key
#'
#' One accumulating cache file: a key once resolved is never re-requested.
#' Backbone reclassification is rare; clear the file to refresh.
#' @noRd
.gbif_species_classification <- function(species_keys, cache_dir, max_active, base_url) {
  cols <- c("speciesKey", "taxon_name", "kingdom", "phylum", "class", "order", "family", "genus")
  path <- if (is.null(cache_dir)) NULL else file.path(cache_dir, "gbif_species_classification.rds")
  known <- if (!is.null(path) && file.exists(path)) {
    tryCatch(readRDS(path), error = function(e) NULL)
  }
  if (is.null(known)) known <- as.data.frame(stats::setNames(replicate(length(cols), character(0), simplify = FALSE), cols))
  need <- setdiff(as.character(species_keys), known$speciesKey)
  if (length(need)) {
    js <- .gbif_get_json_parallel(paste0(base_url, "/species/", need), max(max_active, 8L))
    g <- function(x, f) if (is.null(x[[f]])) NA_character_ else as.character(x[[f]])
    new <- data.frame(
      speciesKey = need,
      taxon_name = vapply(js, function(x) g(x, "species") %|NA|% g(x, "canonicalName"), character(1)),
      kingdom = vapply(js, g, character(1), "kingdom"),
      phylum = vapply(js, g, character(1), "phylum"),
      class = vapply(js, g, character(1), "class"),
      order = vapply(js, g, character(1), "order"),
      family = vapply(js, g, character(1), "family"),
      genus = vapply(js, g, character(1), "genus"),
      stringsAsFactors = FALSE
    )
    known <- rbind(known, new)
    if (!is.null(path)) saveRDS(known, path)
  }
  out <- known[match(as.character(species_keys), known$speciesKey), cols]
  attr(out, "n_fetched") <- length(need)
  out
}

`%|NA|%` <- function(a, b) if (is.na(a)) b else a
