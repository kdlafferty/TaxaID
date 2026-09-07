# ==============================================================================
# taxaflag_clear_cache.R
# TaxaFlag's wrapper over the shared TaxaTools cache engine, matching
# TaxaFetch::taxafetch_clear_cache() / TaxaLikely::taxalikely_clear_cache().
#
# The cache this manages is review_assignments(cache_dir=)'s: one small .rds
# per reviewed taxon, named by a hash of its full key. That is exactly the
# file-per-key shape TaxaTools::list_cache_files() is built for, so it is
# reported and pruned the same way as every other cache in the ecosystem
# rather than accumulating unmanaged.
# ==============================================================================

.taxaflag_cache_patterns <- c("_review\\.rds$")

#' Report and clear TaxaFlag's on-disk review cache
#'
#' Lists, and optionally deletes, the per-taxon files written by
#' [review_assignments()] when it is given a `cache_dir`. Entries have no
#' built-in expiry -- a verdict stays valid until the taxon's own context
#' changes, which changes its key and makes it a miss anyway -- so pruning is
#' about disk usage and about deliberately forcing a fresh review, not about
#' correctness.
#'
#' @param cache_dir Character. The directory passed to
#'   [review_assignments()]'s `cache_dir`. Defaults to
#'   `tools::R_user_dir("TaxaFlag", "cache")`, matching the sibling packages;
#'   workflows that pass a project-local directory should pass the same one
#'   here.
#' @param older_than_days Optional numeric. Delete only entries older than
#'   this many days. `NULL` (default) considers every entry.
#' @param dry_run Logical. `TRUE` reports what would be deleted without
#'   deleting it.
#' @return Invisibly, the inventory data frame
#'   ([TaxaTools::list_cache_files()] output) of the files considered.
#' @seealso [review_assignments()],
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
                                 dry_run = FALSE) {
  inv <- TaxaTools::list_cache_files(cache_dir, .taxaflag_cache_patterns)
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
