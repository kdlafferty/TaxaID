# Kernel priors from per-species GBIF record COUNTS in distance bands, with no
# record download. Same estimator, same output object as
# estimate_kernel_priors(): the bands become count-weighted pseudo-records.

#' Estimate site priors from GBIF band counts (no record download)
#'
#' The fast path to the same prior object [estimate_kernel_priors()]
#' returns. Input is `TaxaFetch::fetch_gbif_occurrence_counts()`: per-species GBIF
#' record counts in concentric distance bands around the site. Each band
#' becomes one pseudo-record carrying its count, placed at the band's
#' representative distance, and the fit is delegated to
#' [estimate_kernel_priors()] with `count_col` -- so `theta`, the Beta
#' parameters, `effective_records`, the regional back-off, the per-group
#' Good-Turing budget and every warning are computed by exactly the same
#' code, and the result slots into [apply_undetected_evidence()],
#' [generate_undetected_diversity()] and the rest unchanged. One site per
#' call: the fit is centred on the single site the counts were fetched
#' around, so each site needs its own count fetch and fit, whereas the
#' records path downloads a polygon once and serves every site inside it
#' ([estimate_kernel_priors()] per site, `TaxaAssign::combine_multisite_priors()`
#' across them).
#'
#' @section Representative distance:
#' A band from `a` to `b` km is given the kernel weight a record would have
#' on average if the band's records were spread uniformly over its annulus,
#' \deqn{\bar w = \frac{2}{b^2-a^2}\int_a^b e^{-r/\lambda} r\,dr,}
#' and placed at the distance with that weight, \eqn{-\lambda \log \bar w}.
#' The regional remainder band (records in the polygon beyond the last
#' break) has no outer edge and is placed at 1.5 times the last break; with
#' the default breaks that is 13.5 bandwidths, where its weight is
#' negligible and it matters only for the regional back-off, which uses
#' unweighted counts.
#'
#' @section Slotting into a workflow:
#' Treat the band table like the occurrence table it replaces. Fetch it
#' with the same taxon keys, search polygon and year range; run the same
#' name standardisation on `taxon_name` (e.g. the GBIF-to-NCBI
#' `verify_taxon_names()` step), because the count table's names are GBIF-backbone
#' names and priors join to candidates by name; add `sampling_group` with
#' the same `TaxaTools::assign_sampling_group()` call; build the habitat
#' lookup with the same `TaxaHabitat::build_habitat_lookup()` call and
#' cache if you use `habitat_filter = "taxon_threshold"`. Records from other
#' sources (a local survey) are read, name-checked and habitat-assigned as
#' before and passed as `extra_occurrences`. The fitted object then goes
#' wherever the kernel fit went.
#'
#' @section What differs from the records path:
#' Measured against the same kernel run on the full GBIF record set for
#' PtConception 18S (1,715 species), the band approximation is within 10x
#' for about 99% of species with `theta >= 1e-4`; it is coarser in the far
#' tail (species whose nearest records are several bandwidths away), where
#' priors are below 1e-6 regardless. What it cannot reproduce:
#' \itemize{
#'   \item \strong{Record-level habitat.} The records path labels every point
#'     from the community recorded there (`TaxaHabitat::assign_habitat_biological()`)
#'     and keeps only points in `site_habitat`. Counts have no points. The
#'     default, `habitat_filter = "none"`, applies no habitat restriction to
#'     the counts and leaves `observed_in_habitat` `NA`.
#'     `"taxon_threshold"` applies habitat per TAXON instead: a species
#'     enters the composition when its `habitat_lookup` weight for
#'     `site_habitat` is at least `habitat_threshold` -- numerator and
#'     denominator alike. Neither is the records path's stratum. The records path keeps a species
#'     whenever its records sit at points labelled `site_habitat`, so at a
#'     coastal site it keeps shoreline terrestrial plants whose own habitat
#'     weight is zero; a taxon-level filter drops them. On PtConception 18S
#'     the taxon filter lost 50 of 377 species with `theta >= 1e-4` in the
#'     record-level Marine stratum, while the unfiltered fit lost none (it
#'     adds taxa the records path excludes instead, which only matters for
#'     taxa that are also match candidates). Check which error your site can
#'     better afford.
#'   \item \strong{A covariate kernel} (e.g. depth) and the |latitude|
#'     factor: both need record coordinates. Not available here.
#'   \item \strong{Bandwidth calibration.} [calibrate_kernel_bandwidth()]
#'     needs records. Reuse a `lambda_km` calibrated for the same region, or
#'     choose one deliberately; it is required, as in the records path.
#'   \item \strong{Singleton coordinates.} `$singletons` carries `NA`
#'     `lat`/`lon` (a band has no point), except for a singleton whose one
#'     supporting record is an `extra_occurrences` row. Nothing downstream
#'     reads them.
#' }
#'
#' @param occurrence_counts Tibble from `TaxaFetch::fetch_gbif_occurrence_counts()`
#'   (columns `taxon_name`, `band_lo_km`, `band_hi_km`, `n`), optionally with
#'   a sampling-group column added by `TaxaTools::assign_sampling_group()`.
#' @param site_habitat Character scalar. Focal habitat.
#' @param lambda_km Numeric scalar. Kernel bandwidth, km. Required.
#' @param m Numeric >= 0. Regional pseudo-records (as in
#'   [estimate_kernel_priors()]).
#' @param habitat_filter How the band counts are restricted to
#'   `site_habitat`. `"none"` (default): every counted taxon enters the
#'   composition. `"taxon_threshold"`: only taxa whose `habitat_lookup` weight
#'   for `site_habitat` is at least `habitat_threshold`. See "What differs
#'   from the records path" for the trade-off. Applies to the band counts
#'   only; `extra_occurrences` carry their own record-level habitat.
#' @param habitat_lookup Data frame or `NULL`. Required for
#'   `habitat_filter = "taxon_threshold"`. Per-taxon habitat weights with a
#'   `taxon_name` column and one numeric column per habitat, named as in
#'   `site_habitat` (the shape `TaxaHabitat::build_habitat_lookup()`
#'   returns). Taxa absent from it are treated like records with no habitat
#'   in the records path: dropped, and counted in a message.
#' @param habitat_threshold Numeric in (0, 1]. Minimum `site_habitat` weight
#'   for a taxon to enter the composition. Default `0.5`, the threshold the
#'   production workflows pass to `assign_habitat_biological()`.
#' @param extra_occurrences Data frame or `NULL`. Point records from sources
#'   other than GBIF (a local survey, a museum table), one row per record,
#'   prepared exactly as for the records path: columns `taxon_name`,
#'   `decimalLatitude`, `decimalLongitude` and a record-level `main_habitat`
#'   (e.g. from `TaxaHabitat::assign_habitat_biological()`), plus the
#'   `sampling_group_col` column when grouping. They are fitted at their true
#'   distances in the same composition as the band counts; only rows whose
#'   `main_habitat` is `site_habitat` count, as in the records path. Make sure
#'   they are not ALSO in GBIF (a dataset published to GBIF would be counted
#'   twice); exclude it from the count query if it is.
#' @param sampling_group_col Optional column in `occurrence_counts` (and
#'   `extra_occurrences`) naming the detection-process group; passed through
#'   to [estimate_kernel_priors()].
#' @param site_id Character or `NULL`, as in [estimate_kernel_priors()].
#' @param support_weight Numeric in (0, 1], as in [estimate_kernel_priors()].
#'   The support radius `-lambda_km * log(support_weight)` should be one of
#'   the band edges (the default edges include `3 * lambda_km`); otherwise the
#'   singleton/doubleton counts are only approximate and a warning says so.
#'
#' @return An object of class `"taxaexpect_kernel_priors"`, as from
#'   [estimate_kernel_priors()], with `params$source = "gbif_counts"`,
#'   `params$breaks_km`, `params$habitat_mode`, `params$habitat_threshold`
#'   and `params$n_extra_records` added.
#' @seealso `TaxaFetch::fetch_gbif_occurrence_counts()`,
#'   `TaxaFetch::plan_gbif_fetch()` for when to use this instead of
#'   the records path.
#' @export
#' @examples
#' bands <- data.frame(
#'   taxon_name = c("A", "A", "B", "B", "C"),
#'   band_lo_km = c(0, 25, 0, 50, 25),
#'   band_hi_km = c(25, 50, 25, 100, 50),
#'   n = c(40, 10, 2, 30, 1)
#' )
#' fp <- suppressWarnings(
#'   estimate_kernel_priors_from_counts(bands, "Marine", lambda_km = 25)
#' )
#' fp$priors[, c("taxon_name", "theta_mean", "effective_records")]
estimate_kernel_priors_from_counts <- function(occurrence_counts,
                                  site_habitat,
                                  lambda_km,
                                  m = 1,
                                  habitat_filter = c("none", "taxon_threshold"),
                                  habitat_lookup = NULL,
                                  habitat_threshold = 0.5,
                                  extra_occurrences = NULL,
                                  sampling_group_col = NULL,
                                  site_id = NULL,
                                  support_weight = exp(-3)) {
  if (!is.data.frame(occurrence_counts) || nrow(occurrence_counts) == 0L) {
    stop("occurrence_counts must be a non-empty data frame from TaxaFetch::fetch_gbif_occurrence_counts().")
  }
  miss <- setdiff(c("taxon_name", "band_lo_km", "band_hi_km", "n"), names(occurrence_counts))
  if (length(miss)) {
    stop(sprintf("occurrence_counts is missing column(s): %s.", paste(miss, collapse = ", ")))
  }
  if (missing(lambda_km) || !is.numeric(lambda_km) || length(lambda_km) != 1L ||
    is.na(lambda_km) || lambda_km <= 0) {
    stop(
      "lambda_km is required: a single positive number. Band counts cannot calibrate it -- ",
      "reuse a calibrate_kernel_bandwidth() result for this region or choose it deliberately."
    )
  }
  if (!is.character(site_habitat) || length(site_habitat) != 1L || is.na(site_habitat)) {
    stop("site_habitat must be a single non-NA character value.")
  }
  q <- attr(occurrence_counts, "query")
  site_lat <- q$site_lat %||% NA_real_
  site_lon <- q$site_lon %||% NA_real_
  site_known <- !is.na(site_lat) && !is.na(site_lon)
  if (!site_known) {
    # Only band DISTANCES enter the fit (no covariate or latitude factor), so
    # any origin gives the same priors; the coordinates only label the site.
    site_lat <- 0
    site_lon <- 0
    if (is.null(site_id)) site_id <- "counts_site"
  }

  x <- as.data.frame(occurrence_counts)
  x <- x[!is.na(x$taxon_name) & x$n > 0, , drop = FALSE]

  # ---- habitat: taxon-level stratification (optional) ----------------------
  habitat_filter <- match.arg(habitat_filter)
  habitat_mode <- habitat_filter
  if (habitat_filter == "taxon_threshold") {
    if (is.null(habitat_lookup) || !all(c("taxon_name", site_habitat) %in% names(habitat_lookup))) {
      stop(sprintf("habitat_filter = \"taxon_threshold\" needs a habitat_lookup with columns 'taxon_name' and '%s'.", site_habitat))
    }
    if (!is.numeric(habitat_threshold) || length(habitat_threshold) != 1L ||
      is.na(habitat_threshold) || habitat_threshold <= 0 || habitat_threshold > 1) {
      stop("habitat_threshold must be a single number in (0, 1].")
    }
    hw <- habitat_lookup[[site_habitat]][match(x$taxon_name, habitat_lookup$taxon_name)]
    n_unknown <- length(unique(x$taxon_name[is.na(hw)]))
    if (n_unknown > 0L) {
      message(sprintf(
        "estimate_kernel_priors_from_counts: %d taxa have no habitat_lookup entry and are dropped (%s records), as NA-habitat records are in the records path.",
        n_unknown, format(sum(x$n[is.na(hw)]), big.mark = ",")
      ))
    }
    x$main_habitat <- ifelse(!is.na(hw) & hw >= habitat_threshold, site_habitat, NA_character_)
  } else {
    if (!is.null(habitat_lookup)) {
      message("estimate_kernel_priors_from_counts: habitat_lookup is ignored with habitat_filter = \"none\".")
    }
    message(
      "estimate_kernel_priors_from_counts: habitat_filter = \"none\" -- every counted taxon enters the '",
      site_habitat, "' composition."
    )
    x$main_habitat <- site_habitat
  }

  # ---- bands -> pseudo-records ---------------------------------------------
  lo <- x$band_lo_km
  hi <- x$band_hi_km
  last <- max(hi[is.finite(hi)])
  x$d_km <- ifelse(is.finite(hi), .band_representative_km(lo, hi, lambda_km), 1.5 * last)
  sup_r <- -lambda_km * log(support_weight)
  edges <- unique(c(lo, hi[is.finite(hi)]))
  if (!any(abs(edges - sup_r) <= 1e-6 * sup_r)) {
    warning(sprintf(
      "estimate_kernel_priors_from_counts: the support radius (%.1f km = -lambda_km * log(support_weight)) is not a band edge, so f1/f2 (and theta_present) are approximate. Fetch with lambda_km = %g to get matching default bands.",
      sup_r, lambda_km
    ), call. = FALSE)
  }
  off <- x$d_km / (111 * cos(site_lat * pi / 180))
  if (any(off >= 180)) stop("A band lies more than half the globe away in longitude; use smaller breaks.")
  x$decimalLatitude <- site_lat
  x$decimalLongitude <- site_lon + off

  # ---- extra point records (non-GBIF sources) ---------------------------
  n_extra <- 0L
  ex <- NULL
  if (!is.null(extra_occurrences)) {
    if (!site_known) {
      stop("extra_occurrences need the real site coordinates, but occurrence_counts carries none (attr 'query').")
    }
    need <- c("taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat", sampling_group_col)
    miss <- setdiff(need, names(extra_occurrences))
    if (length(miss)) {
      stop(sprintf("extra_occurrences is missing column(s): %s.", paste(miss, collapse = ", ")))
    }
    ex <- as.data.frame(extra_occurrences)[, need, drop = FALSE]
    ex$n <- 1
    n_extra <- sum(!is.na(ex$main_habitat) & ex$main_habitat == site_habitat)
    message(sprintf(
      "estimate_kernel_priors_from_counts: %s extra record(s) in '%s' join the fit at their own coordinates.",
      format(n_extra, big.mark = ","), site_habitat
    ))
    keep_cols <- c("taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat", sampling_group_col, "n")
    x <- rbind(x[, keep_cols, drop = FALSE], ex[, keep_cols, drop = FALSE])
  }

  fit <- estimate_kernel_priors(
    x, site_lat, site_lon, site_habitat,
    lambda_km = lambda_km, m = m, site_id = site_id,
    sampling_group_col = sampling_group_col, count_col = "n",
    support_weight = support_weight
  )
  # Pseudo-record positions are not places; do not let them look like ones.
  # A singleton whose one supporting record is a real extra record keeps
  # that record's coordinates.
  if (nrow(fit$singletons)) {
    fit$singletons$lat <- NA_real_
    fit$singletons$lon <- NA_real_
    if (!is.null(ex)) {
      d_ex <- .approx_distance_km(ex$decimalLatitude, ex$decimalLongitude, site_lat, site_lon, site_lat)
      sup_ex <- ex[!is.na(ex$main_habitat) & ex$main_habitat == site_habitat & d_ex <= sup_r, , drop = FALSE]
      j <- match(fit$singletons$taxon_name, sup_ex$taxon_name)
      fit$singletons$lat <- sup_ex$decimalLatitude[j]
      fit$singletons$lon <- sup_ex$decimalLongitude[j]
    }
  }
  if (habitat_mode == "none") fit$priors$observed_in_habitat <- NA
  fit$params$source <- "gbif_counts"
  fit$params$breaks_km <- sort(unique(hi[is.finite(hi)]))
  fit$params$habitat_mode <- habitat_mode
  fit$params$habitat_threshold <- if (habitat_mode == "none") NULL else habitat_threshold
  fit$params$n_extra_records <- n_extra
  fit
}

#' Distance whose kernel weight equals the annulus-average weight
#' (uniform record density over the annulus from a to b km).
#' @noRd
.band_representative_km <- function(a, b, lambda) {
  f <- function(r) -lambda * (r + lambda) * exp(-r / lambda) # antiderivative of r e^{-r/l}
  wbar <- 2 * (f(b) - f(a)) / (b^2 - a^2)
  -lambda * log(wbar)
}
