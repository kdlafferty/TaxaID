# ==============================================================================
# plan_gbif_fetch.R
# TaxaFetch -- Size a GBIF pull and price the records path vs the counts path
# ==============================================================================

#' Plan a GBIF fetch: price the records path against the counts path
#'
#' Asks GBIF, with a handful of count-only requests, how big the occurrence
#' pull for these keys, polygon and years would be, then prices both prior
#' paths:
#' \describe{
#'   \item{records path}{[download_gbif_occurrences()] ->
#'     [filter_gbif_quality()] -> habitat assignment -> spatial review ->
#'     `TaxaExpect::estimate_kernel_priors()`. Cost grows with the number of
#'     RECORDS.}
#'   \item{counts path}{[fetch_gbif_occurrence_counts()] ->
#'     `TaxaExpect::estimate_kernel_priors_from_counts()`. Cost grows with the number of
#'     distinct SPECIES not yet in the name cache, and is independent of the
#'     number of records.}
#' }
#' The counts-path figures price one site; this function takes no site
#' coordinates. A multi-site study should compare one records download
#' against as many count fetches as it has sites (multiply `counts_requests`
#' and `counts_min` by the number of sites; the species-name lookups are
#' shared through the cache, so later sites cost only the band requests).
#'
#' @section Which path:
#' Choose by what the prior needs first and by size second. The records path
#' is the only one that supports record-level habitat assignment, a
#' covariate kernel (e.g. depth), bandwidth calibration
#' (`TaxaExpect::calibrate_kernel_bandwidth()`), spatial review of individual
#' records, and merging non-GBIF records (local surveys) into the same pool;
#' if the analysis needs any of them, use it whenever it fits in memory.
#' Otherwise the counts path gives the same kernel prior to within an order of
#' magnitude for the species that matter, in seconds to minutes, and it is the
#' only feasible path once the pool runs to many millions of records. The
#' recommendation returned here applies that rule: counts when the records
#' path's estimated peak memory exceeds `ram_fraction` of `ram_gb` or the
#' pool exceeds `max_records`, records path otherwise.
#'
#' @section Rates behind the estimates:
#' Measured on the PtConception 18S pool (1.72 million records, Apple
#' silicon laptop) and exposed as `rates` so they can be re-measured:
#' `download_bytes_per_record` 410 (the zip), `filter_sec_per_million` 240
#' ([filter_gbif_quality()], the dominant automated per-record step; habitat
#' assignment and resolution together took under 10 s per 300,000 records),
#' `filter_gb_per_million` 4 (peak R memory of [filter_gbif_quality()]),
#' `counts_sec_per_request` 0.25 and `name_lookups_per_sec` 28 (the counts
#' path's band requests and uncached species-name lookups), and
#' `download_queue_min` 10 (GBIF's server-side preparation time; it varies with
#' GBIF load and is the least predictable term). Not priced for either path:
#' LLM habitat lookups per taxon (the same per-taxon cost on both paths, and
#' cached) and, on the records path, interactive spatial review, which is paid
#' in reviewer time per flagged point.
#'
#' @inheritParams fetch_gbif_occurrence_counts
#' @param ram_gb Numeric or `NULL`. Physical memory to compare the record
#'   path's peak against. `NULL`: detected on macOS and Linux, otherwise `NA`
#'   (no memory-based recommendation).
#' @param ram_fraction Numeric. Share of `ram_gb` the records path may use
#'   before the counts path is recommended. Default 0.5.
#' @param max_records Numeric. Pool size above which the counts path is
#'   recommended regardless of memory. Default 5 million.
#' @param rates Named list overriding any of the rates above.
#'
#' @return A one-row tibble: `n_records` (rows the records path would
#'   download), `n_species_records` (of those, resolved to species),
#'   `n_species`, `n_species_uncached`, `records_download_mb`,
#'   `records_queue_min`, `records_process_min`, `records_peak_gb`,
#'   `counts_requests`, `counts_min`, `ram_gb`, `recommended`
#'   (`"records"` or `"counts"`) and `reason`.
#' @seealso [fetch_gbif_occurrence_counts()], [download_gbif_occurrences()]
#' @export
#' @examples
#' \dontrun{
#' plan_gbif_fetch(valid_keys, geometry = bbox, lambda_km = 25,
#'   year_range = "1995,2026")
#' }
plan_gbif_fetch <- function(keys,
                                     geometry = NULL,
                                     lambda_km = NULL,
                                     breaks_km = NULL,
                                     year_range = .gbif_default_year_range(),
                                     basis_of_record = NULL,
                                     key_batch_size = 150L,
                                     cache_dir = tools::R_user_dir("TaxaFetch", "cache"),
                                     ram_gb = NULL,
                                     ram_fraction = 0.5,
                                     max_records = 5e6,
                                     rates = list(),
                                     max_active = 4L,
                                     base_url = "https://api.gbif.org/v1") {
  r <- utils::modifyList(list(
    download_bytes_per_record = 410, filter_sec_per_million = 240,
    filter_gb_per_million = 4, counts_sec_per_request = 0.25,
    name_lookups_per_sec = 28, download_queue_min = 10
  ), rates)
  keys <- sort(unique(stats::na.omit(as.numeric(keys))))
  if (!length(keys)) stop("plan_gbif_fetch: `keys` is empty.")
  n_bands <- if (!is.null(breaks_km)) length(breaks_km) else if (!is.null(lambda_km)) 9L else {
    stop("plan_gbif_fetch: supply `lambda_km` or `breaks_km`, as for fetch_gbif_occurrence_counts().")
  }
  n_bands <- n_bands + as.integer(!is.null(geometry))

  batches <- split(keys, ceiling(seq_along(keys) / key_batch_size))
  base <- paste0(
    base_url, "/occurrence/search?limit=0&occurrenceStatus=PRESENT&hasCoordinate=true&hasGeospatialIssue=false",
    "&facet=speciesKey&facetLimit=", .facet_limit,
    if (!is.null(year_range)) paste0("&year=", year_range) else "",
    if (length(basis_of_record)) paste0("&basisOfRecord=", basis_of_record, collapse = "") else "",
    if (!is.null(geometry)) paste0("&geometry=", utils::URLencode(geometry, reserved = TRUE)) else ""
  )
  urls <- vapply(batches, function(b) {
    paste0(base, paste0("&taxonKey=", format(b, scientific = FALSE, trim = TRUE), collapse = ""))
  }, character(1))
  res <- .gbif_get_json_parallel(urls, max_active)
  n_records <- sum(vapply(res, function(z) as.numeric(z$count), numeric(1)))
  sp <- unlist(lapply(res, function(z) {
    cnt <- if (length(z$facets)) z$facets[[1L]]$counts else list()
    stats::setNames(vapply(cnt, function(y) as.numeric(y$count), numeric(1)),
                    vapply(cnt, function(y) as.character(y$name), character(1)))
  }))
  sp <- tapply(sp, names(sp), sum)
  n_species <- length(sp)
  known <- character(0)
  path <- if (is.null(cache_dir)) NULL else file.path(cache_dir, "gbif_species_classification.rds")
  if (!is.null(path) && file.exists(path)) {
    known <- tryCatch(readRDS(path)$speciesKey, error = function(e) character(0))
  }
  n_uncached <- sum(!names(sp) %in% known)

  if (is.null(ram_gb)) ram_gb <- .physical_ram_gb()
  M <- n_records / 1e6
  peak_gb <- M * r$filter_gb_per_million
  counts_requests <- n_bands * length(batches) + n_uncached
  counts_min <- (n_bands * length(batches) * r$counts_sec_per_request / max_active +
    n_uncached / r$name_lookups_per_sec) / 60

  mem_bad <- is.finite(ram_gb) && peak_gb > ram_fraction * ram_gb
  big <- n_records > max_records
  recommended <- if (mem_bad || big) "counts" else "records"
  reason <- if (mem_bad) {
    sprintf("records path needs ~%.0f GB at peak, over %.0f%% of %.0f GB RAM", peak_gb, 100 * ram_fraction, ram_gb)
  } else if (big) {
    sprintf("%s records exceeds max_records (%s)", format(n_records, big.mark = ","), format(max_records, big.mark = ","))
  } else {
    "records path fits in memory; it keeps record-level habitat, covariates, calibration and spatial review"
  }
  out <- tibble::tibble(
    n_records = n_records, n_species_records = sum(sp), n_species = n_species,
    n_species_uncached = n_uncached,
    records_download_mb = n_records * r$download_bytes_per_record / 1e6,
    records_queue_min = r$download_queue_min,
    records_process_min = M * r$filter_sec_per_million / 60,
    records_peak_gb = peak_gb,
    counts_requests = counts_requests, counts_min = counts_min,
    ram_gb = ram_gb, recommended = recommended, reason = reason
  )
  message(sprintf(
    paste0(
      "GBIF pool: %s records (%s at species level), %s species (%s not in the name cache).\n",
      "  records path: ~%.0f MB download + GBIF queue (~%g min, variable) + ~%.1f min cleaning, peak ~%.1f GB\n",
      "  counts path : %s requests, ~%.1f min\n",
      "  recommended: %s -- %s"
    ),
    format(n_records, big.mark = ","), format(sum(sp), big.mark = ","),
    format(n_species, big.mark = ","), format(n_uncached, big.mark = ","),
    out$records_download_mb, r$download_queue_min, out$records_process_min, peak_gb,
    format(counts_requests, big.mark = ","), counts_min, recommended, reason
  ))
  out
}

#' Physical RAM in GB (macOS/Linux), NA elsewhere or on failure
#' @noRd
.physical_ram_gb <- function() {
  sys <- Sys.info()[["sysname"]]
  b <- tryCatch(
    if (sys == "Darwin") {
      as.numeric(system("sysctl -n hw.memsize", intern = TRUE))
    } else if (sys == "Linux") {
      kb <- as.numeric(sub("\\D+(\\d+).*", "\\1", grep("^MemTotal", readLines("/proc/meminfo"), value = TRUE)))
      kb * 1024
    } else {
      NA_real_
    },
    error = function(e) NA_real_, warning = function(w) NA_real_
  )
  b / 1024^3
}
