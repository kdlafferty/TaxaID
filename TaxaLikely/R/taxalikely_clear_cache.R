# ==============================================================================
# taxalikely_clear_cache.R
# TaxaLikely -- report and clear the persistent on-disk cache
#
# Built on TaxaTools::list_cache_files()/report_and_clear_cache() (the shared
# file-per-key cache engine also used by TaxaFetch::taxafetch_clear_cache()).
#
# Each query maps to one deterministic file with no overwrite concept, but
# that does not mean there is no duplicate/orphan-accumulation mechanism:
# the accumulation mechanism is KEY WIDENING. Every time
# a real staleness crash is fixed by adding a component to the cache key,
# the entire previous generation is silently orphaned rather than replaced
# -- confirmed on a real cache directory, 1,584 of 3,517 meta files (45%).
# Hence the automatic write-path eviction in fetch.R (.ref_cache_evict()).
# ==============================================================================

#' Recognized TaxaLikely cache file patterns
#'
#' Per-taxon reference-fetch metadata (\code{fetch_ncbi_reference_sequences()}),
#' per-genus coverage checkpoints (\code{audit_barcode_coverage()}), and the
#' per-accession FASTA store, which
#' lives in a \code{fasta/} SUBDIRECTORY and so needs a recursive scan --
#' while it had neither a pattern nor a recursive scan, its 4,061 files were
#' invisible to every clear function in the ecosystem.
#' @noRd
.taxalikely_cache_patterns <- c("_meta\\.rds$", "_ckpt\\.rds$", "_seq\\.rds$")


#' Report and clear TaxaLikely's on-disk cache
#'
#' \code{fetch_ncbi_reference_sequences()} caches one small file per
#' (taxon, barcode_term, length window, date range, out-of-range settings,
#' rank_system) combination it has ever been asked for, plus one file per
#' accession under \code{fasta/}; \code{audit_barcode_coverage()} caches one
#' checkpoint per (rank, marker, params) combination it has run. All cache
#' under a persistent, user-level directory and none expires automatically.
#' This function reports how much space the cache is using and, unless
#' \code{dry_run = TRUE}, removes it.
#'
#' It is the blunt instrument: it targets EVERY recognized cache file,
#' whether or not a later call could still hit it -- including
#' generations superseded by a cache-key widening (45% of the meta store on
#' a real cache directory). The automatic write-path eviction in
#' \code{fetch_ncbi_reference_sequences()} removes only those provably-dead
#' files, scoped to the taxon just rewritten, on every fetch.
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
  inv <- TaxaTools::list_cache_files(
    cache_dir, .taxalikely_cache_patterns,
    recursive = TRUE
  )
  TaxaTools::report_and_clear_cache(
    inv,
    label = "taxalikely_clear_cache", cache_dir = cache_dir,
    older_than_days = older_than_days, dry_run = dry_run
  )
}
