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
#' @param dry_run Logical. If \code{TRUE}, reports what would be removed
#'   without removing anything. Default \code{FALSE}.
#' @return Invisibly, a data frame of the targeted files (\code{path},
#'   \code{size_mb}, \code{mtime}), possibly zero rows.
#' @export
#' @examples
#' \dontrun{
#' taxafetch_clear_cache(dry_run = TRUE)                       # see what's there first
#' taxafetch_clear_cache(orphans_only = TRUE, dry_run = TRUE)   # just stale leftovers
#' taxafetch_clear_cache(orphans_only = TRUE)                   # remove just those
#' taxafetch_clear_cache()                                      # actually clear everything
#' taxafetch_clear_cache(older_than_days = 90)                  # only stale entries
#' }
taxafetch_clear_cache <- function(cache_dir = tools::R_user_dir("TaxaFetch", "cache"),
                                   older_than_days = NULL,
                                   orphans_only = FALSE,
                                   dry_run = FALSE) {
  if (!is.logical(orphans_only) || length(orphans_only) != 1L || is.na(orphans_only)) {
    stop("taxafetch_clear_cache: 'orphans_only' must be TRUE or FALSE.")
  }

  inv <- TaxaTools::list_cache_files(cache_dir, .taxafetch_cache_patterns)

  if (isTRUE(orphans_only)) {
    referenced <- basename(.taxafetch_referenced_zips(cache_dir))
    is_zip     <- grepl("\\.zip$", basename(inv$path))
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
    inv, label = "taxafetch_clear_cache", cache_dir = cache_dir,
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
  if (length(meta_files) == 0L) return(character(0))

  paths <- vapply(meta_files, function(f) {
    meta <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.list(meta) && !is.null(meta$zip_path)) as.character(meta$zip_path) else NA_character_
  }, character(1))

  unique(stats::na.omit(paths))
}
