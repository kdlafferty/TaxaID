# ==============================================================================
# taxaflag_clear_cache.R
# TaxaFlag's wrapper over the shared TaxaTools cache engine, matching
# TaxaFetch::taxafetch_clear_cache() / TaxaLikely::taxalikely_clear_cache().
#
# TWO caches share this one management function, both one small .rds per
# key, named by a hash of the full key -- exactly the file-per-key shape
# TaxaTools::list_cache_files() is built for, so both are reported and
# pruned the same way as every other cache in the ecosystem rather than
# accumulating unmanaged:
#   1. review_assignments(cache_dir=)'s per-reviewed-taxon LLM verdict cache
#      (files ending "_review.rds").
#   2. check_gbif_tile_range(cache_dir=)'s per-(taxon, location, zoom, ...)
#      GBIF density-tile verdict cache (files ending "_tile_range.rds").
# ==============================================================================

.taxaflag_cache_patterns <- c("_review\\.rds$", "_tile_range\\.rds$")

#' Report and clear TaxaFlag's on-disk caches
#'
#' Lists, and optionally deletes, the per-key files written by
#' [review_assignments()] and [check_gbif_tile_range()] when either is given
#' a `cache_dir`: [review_assignments()]'s per-reviewed-taxon LLM verdict
#' cache, and [check_gbif_tile_range()]'s per-(taxon, location, zoom, ...)
#' GBIF density-tile verdict cache. Entries in both have no built-in expiry
#' -- a verdict stays valid until its own key changes (e.g. the taxon's
#' review context changes, or the query location/zoom changes), which makes
#' it a miss anyway -- so pruning is about disk usage and about deliberately
#' forcing a fresh review/re-fetch, not about correctness.
#'
#' @param cache_dir Character. The directory passed to
#'   [review_assignments()]'s or [check_gbif_tile_range()]'s `cache_dir`
#'   (each function's cache lives in its own directory, so point this at
#'   whichever one you want to inspect/clear). Defaults to
#'   `tools::R_user_dir("TaxaFlag", "cache")`, matching the sibling packages;
#'   workflows that pass a project-local directory should pass the same one
#'   here.
#' @param older_than_days Optional numeric. Delete only entries older than
#'   this many days. `NULL` (default) considers every entry.
#' @param dry_run Logical. `TRUE` reports what would be deleted without
#'   deleting it.
#' @param force Logical (default `FALSE`). Pass `TRUE` to clear a
#'   `cache_dir` that holds file(s) matching none of the recognized cache
#'   patterns -- see `TaxaTools::list_cache_files()`.
#' @return Invisibly, the inventory data frame
#'   ([TaxaTools::list_cache_files()] output) of the files considered.
#' @seealso [review_assignments()], [check_gbif_tile_range()],
#'   [TaxaTools::report_and_clear_cache()],
#'   `TaxaFetch::taxafetch_clear_cache()`, `TaxaLikely::taxalikely_clear_cache()`
#' @export
#' @examples
#' \dontrun{
#' taxaflag_clear_cache(dry_run = TRUE) # report only
#' taxaflag_clear_cache(older_than_days = 90) # prune old entries
#' }
taxaflag_clear_cache <- function(cache_dir = tools::R_user_dir("TaxaFlag", "cache"),
                                 older_than_days = NULL,
                                 dry_run = FALSE,
                                 force = FALSE) {
  inv <- TaxaTools::list_cache_files(cache_dir, .taxaflag_cache_patterns, force = force)
  TaxaTools::report_and_clear_cache(
    inv,
    label = "taxaflag_clear_cache", cache_dir = cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}

# ------------------------------------------------------------------------------
# Internal cache helpers for review_assignments(cache_dir=)
# ------------------------------------------------------------------------------

#' Filename hash for a review cache key
#'
#' Deliberately NOT relied on for correctness: the full key is stored inside
#' the file and checked on read (see .review_cache_read), so a collision costs
#' one re-asked taxon rather than returning another taxon's verdict. Base R
#' only, no new dependency.
#' @noRd
.review_cache_hash <- function(x) {
  ints <- utf8ToInt(x)
  n <- length(ints)
  if (n == 0L) {
    return("empty-0-0")
  }
  v <- as.numeric(ints)
  a <- sum(v * seq_len(n)) %% 2147483647
  b <- sum(v * rev(seq_len(n))) %% 1000000007
  sprintf("%010.0f-%010.0f-%06d", a, b, n)
}

#' Read one cached review row, verifying its full key
#' @noRd
.review_cache_read <- function(path, key) {
  if (!file.exists(path)) {
    return(NULL)
  }
  ent <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(ent) || !is.list(ent) || is.null(ent$key) || is.null(ent$row)) {
    return(NULL)
  }
  if (!identical(ent$key, key)) {
    return(NULL)
  } # collision or stale layout
  if (!is.data.frame(ent$row) || nrow(ent$row) != 1L) {
    return(NULL)
  }
  ent$row
}

#' Write one review row to the cache, alongside its full key
#' @noRd
.review_cache_write <- function(path, key, row) {
  tryCatch(saveRDS(list(key = key, row = row), path),
    error = function(e) invisible(NULL)
  )
  invisible(NULL)
}
