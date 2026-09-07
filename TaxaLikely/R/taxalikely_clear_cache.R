# ==============================================================================
# taxalikely_clear_cache.R
# TaxaLikely -- report and clear the persistent on-disk cache
#
# Built on TaxaTools::list_cache_files()/report_and_clear_cache() (the shared
# file-per-key cache engine also used by TaxaFetch::taxafetch_clear_cache()).
# Unlike TaxaFetch's GBIF download cache, there is no known duplicate/orphan-
# accumulation mechanism here (each query maps to exactly one deterministic
# file, with no "overwrite" concept to leave a stale copy behind), so this is
# purely a reporting/size-cap tool, not a bug fix.
# ==============================================================================

#' Recognized TaxaLikely cache file patterns
#'
#' Per-taxon reference-fetch metadata (\code{fetch_ncbi_reference_sequences()})
#' and per-genus coverage checkpoints (\code{audit_barcode_coverage()}).
#' @noRd
.taxalikely_cache_patterns <- c("_meta\\.rds$", "_ckpt\\.rds$")


#' Report and clear TaxaLikely's on-disk cache
#'
#' \code{fetch_ncbi_reference_sequences()} caches one small file per
#' (taxon, barcode_term, length window, date range, out-of-range settings,
#' rank_system) combination it has ever been asked for; \code{audit_barcode_
#' coverage()} caches one checkpoint per (rank, marker, params) combination
#' it has run. Both cache under a persistent, user-level directory and
#' neither expires automatically -- unlike TaxaFetch's GBIF download cache,
#' there is no known duplicate/orphan-accumulation mechanism here (each
#' query maps to exactly one deterministic file, with no "overwrite" concept
#' to leave a stale copy behind), so this is purely a reporting/size-cap
#' tool, not a bug fix. This function reports how much space the cache is
#' using and, unless \code{dry_run = TRUE}, removes it.
#'
#' @param cache_dir Character. Cache directory to inspect/clear. Defaults to
#'   \code{tools::R_user_dir("TaxaLikely", "cache")}, the same default used
#'   by \code{fetch_ncbi_reference_sequences()}/\code{audit_barcode_coverage()}.
#' @param older_than_days Numeric or \code{NULL}. When supplied, only files
#'   older than this many days (by modification time) are targeted.
#'   \code{NULL} (default) targets every recognized cache file in
#'   \code{cache_dir}.
#' @param dry_run Logical. If \code{TRUE}, reports what would be removed
#'   without removing anything. Default \code{FALSE}.
#' @return Invisibly, a data frame of the targeted files (\code{path},
#'   \code{size_mb}, \code{mtime}), possibly zero rows.
#' @export
#' @examples
#' \dontrun{
#' taxalikely_clear_cache(dry_run = TRUE) # see what's there first
#' taxalikely_clear_cache() # actually clear it
#' taxalikely_clear_cache(older_than_days = 180) # only stale entries
#' }
taxalikely_clear_cache <- function(cache_dir = tools::R_user_dir("TaxaLikely", "cache"),
                                   older_than_days = NULL,
                                   dry_run = FALSE) {
  inv <- TaxaTools::list_cache_files(cache_dir, .taxalikely_cache_patterns)
  TaxaTools::report_and_clear_cache(
    inv,
    label = "taxalikely_clear_cache", cache_dir = cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}
