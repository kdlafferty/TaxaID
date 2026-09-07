# ==============================================================================
# taxafetch_clear_cache.R
# TaxaFetch -- report and clear the persistent on-disk cache
#
# Built on TaxaTools::list_cache_files()/report_and_clear_cache() (the
# shared file-per-key cache engine also used by
# TaxaLikely::taxalikely_clear_cache()) -- orphan detection is the only
# genuinely TaxaFetch-specific piece, since it depends on
# download_gbif_occurrences()'s own metadata-file format, so it stays here
# as a pre-filter in front of the shared engine.
# ==============================================================================

#' Recognized TaxaFetch cache file patterns
#'
#' GBIF download zips + their metadata companions
#' (\code{download_gbif_occurrences()}), GBIF checkpoint files
#' (\code{fetch_gbif_occurrences()}), iNaturalist range GeoJSON files
#' (\code{check_inat_range()}), and OpenAlex literature-search cache files
#' (\code{search_literature(cache_dir=)}, disabled by default but the same
#' file shape if a caller points it at a shared cache directory).
#' @noRd
.taxafetch_cache_patterns <- c(
  "\\.zip$", "^gbif_dl_.*_meta\\.rds$", "^gbif_fetch_.*\\.rds$",
  "\\.geojson$", "^openalex_cache_.*\\.rds$"
)


#' Report and clear TaxaFetch's on-disk cache
#'
#' TaxaFetch caches GBIF download zips (\code{download_gbif_occurrences()}),
#' checkpoint files (\code{fetch_gbif_occurrences()}), iNaturalist range
#' polygons (\code{check_inat_range()}), and (if enabled) OpenAlex literature
#' results (\code{search_literature()}) under a persistent, user-level cache
#' directory. None of these expire automatically -- GBIF zips in particular
#' are permanent until removed by hand. This function reports how much space
#' the cache is using and, unless \code{dry_run = TRUE}, removes it.
#'
#' @param cache_dir Character. Cache directory to inspect/clear. Defaults to
#'   \code{tools::R_user_dir("TaxaFetch", "cache")}, the same default used by
#'   \code{download_gbif_occurrences()}/\code{fetch_gbif_occurrences()}/
#'   \code{check_geographic_outliers()}.
#' @param older_than_days Numeric or \code{NULL}. When supplied, only files
#'   older than this many days (by modification time) are targeted.
#'   \code{NULL} (default) targets every recognized cache file in
#'   \code{cache_dir}.
#' @param orphans_only Logical. If \code{TRUE}, targets only GBIF download
#'   zips that are no longer referenced by any current
#'   \code{download_gbif_occurrences()} metadata file in \code{cache_dir} --
#'   i.e. zips superseded by a later \code{overwrite = TRUE} run before this
#'   package's 2026-09-03 orphan-cleanup fix. The zip each metadata file
#'   currently points to (its query's most recent cached download), every
#'   metadata file itself, every \code{fetch_gbif_occurrences()} checkpoint,
#'   and every iNaturalist range file are left untouched -- this is the
#'   "keep the most recent cache per query, remove only stale leftovers"
#'   mode. Default \code{FALSE} (target everything recognized, the same as
#'   before this parameter existed).
#' @param zips_only Logical. If \code{TRUE}, targets only the downloaded GBIF
#'   \code{.zip} files, leaving every metadata file and \code{.rds} checkpoint
#'   in place. This is usually the setting you want for reclaiming space: the
#'   zips are the cache in practice (38 of them held 17 GB on one real machine,
#'   against 52 MB for every \code{.rds} combined), they are pure redundancy
#'   once imported, and keeping their metadata means a later identical call
#'   re-fetches the same prepared GBIF key with no new request or queue wait.
#'   Unlike \code{orphans_only} this includes zips still referenced by current
#'   metadata -- those are exactly the large ones. Cannot be combined with
#'   \code{orphans_only}.
#' @param dry_run Logical. If \code{TRUE}, reports what would be removed
#'   without removing anything. Default \code{FALSE}.
#' @return Invisibly, a data frame of the targeted files (\code{path},
#'   \code{size_mb}, \code{mtime}), possibly zero rows.
#' @export
#' @examples
#' \dontrun{
#' taxafetch_clear_cache(dry_run = TRUE) # see what's there first
#' taxafetch_clear_cache(orphans_only = TRUE, dry_run = TRUE) # just stale leftovers
#' taxafetch_clear_cache(orphans_only = TRUE) # remove just those
#' taxafetch_clear_cache() # actually clear everything
#' taxafetch_clear_cache(older_than_days = 90) # only stale entries
#' }
taxafetch_clear_cache <- function(cache_dir = tools::R_user_dir("TaxaFetch", "cache"),
                                  older_than_days = NULL,
                                  orphans_only = FALSE,
                                  zips_only = FALSE,
                                  dry_run = FALSE) {
  if (!is.logical(orphans_only) || length(orphans_only) != 1L || is.na(orphans_only)) {
    stop("taxafetch_clear_cache: 'orphans_only' must be TRUE or FALSE.")
  }
  if (!is.logical(zips_only) || length(zips_only) != 1L || is.na(zips_only)) {
    stop("taxafetch_clear_cache: 'zips_only' must be TRUE or FALSE.")
  }
  if (isTRUE(orphans_only) && isTRUE(zips_only)) {
    stop(
      "taxafetch_clear_cache: use either 'orphans_only' or 'zips_only', not both -- ",
      "orphans_only already targets a subset of the zips."
    )
  }

  inv <- TaxaTools::list_cache_files(cache_dir, .taxafetch_cache_patterns)

  if (isTRUE(zips_only)) {
    # The zips ARE the cache, in practice: on one real machine 38 of them held
    # 17 GB while every .rds checkpoint together came to 52 MB. A zip is pure
    # redundancy once imported -- its only value is avoiding a re-download --
    # and the small metadata files are deliberately LEFT BEHIND, so each
    # query's download key survives and a later identical call re-fetches that
    # same prepared file rather than queueing a new request.
    is_zip <- grepl("\\.zip$", basename(inv$path))
    inv <- inv[is_zip, , drop = FALSE]
    if (nrow(inv) == 0L) {
      message("taxafetch_clear_cache: no cached zips found.")
      return(invisible(inv))
    }
    message(sprintf(
      "taxafetch_clear_cache: targeting %d zip(s); metadata kept so the download keys stay re-fetchable.",
      nrow(inv)
    ))
  }

  if (isTRUE(orphans_only)) {
    referenced <- basename(.taxafetch_referenced_zips(cache_dir))
    is_zip <- grepl("\\.zip$", basename(inv$path))
    inv <- inv[is_zip & !(basename(inv$path) %in% referenced), , drop = FALSE]
    if (nrow(inv) == 0L) {
      message(
        "taxafetch_clear_cache: no orphaned zips found -- every cached zip ",
        "is still the current one for its query."
      )
      return(invisible(inv))
    }
  }

  TaxaTools::report_and_clear_cache(
    inv,
    label = "taxafetch_clear_cache", cache_dir = cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}


#' List the zip files current metadata entries point to
#'
#' Reads every \code{gbif_dl_*_meta.rds} file in \code{cache_dir} and
#' collects the \code{zip_path} each one currently points to -- i.e. the
#' single zip that IS the most recent cached download for that query
#' signature. Any \code{.zip} file in \code{cache_dir} not in this set was
#' superseded by a later run and never cleaned up (only possible from a
#' run predating the 2026-09-03 orphan-cleanup fix).
#'
#' @param cache_dir Character. Directory to scan.
#' @return A character vector of referenced zip paths (possibly empty).
#' @noRd
.taxafetch_referenced_zips <- function(cache_dir) {
  meta_files <- list.files(cache_dir, pattern = "^gbif_dl_.*_meta\\.rds$", full.names = TRUE)
  if (length(meta_files) == 0L) {
    return(character(0))
  }

  paths <- vapply(meta_files, function(f) {
    meta <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.list(meta) && !is.null(meta$zip_path)) as.character(meta$zip_path) else NA_character_
  }, character(1))

  unique(stats::na.omit(paths))
}
