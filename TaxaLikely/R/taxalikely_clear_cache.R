# ==============================================================================
# taxalikely_clear_cache.R
# TaxaLikely -- report and clear the persistent on-disk cache
#
# Built on TaxaTools::list_cache_files()/report_and_clear_cache() (the shared
# file-per-key cache engine also used by TaxaFetch::taxafetch_clear_cache()).
#
# CORRECTED 2026-09-14. This file used to claim there was "no known
# duplicate/orphan-accumulation mechanism here" because each query maps to
# one deterministic file with no overwrite concept. That is wrong, and the
# measurement is in ecosystem_docs/CACHE_POLICY_REVIEW_2026_09_14.md: the
# accumulation mechanism is not overwriting, it is KEY WIDENING. Every time
# a real staleness crash was fixed by adding a component to the cache key,
# the entire previous generation was silently orphaned rather than replaced
# -- 1,584 of 3,517 meta files (45%) on the development machine. Hence
# taxalikely_evict_unreachable_cache() below, and the automatic write-path
# eviction in fetch.R.
# ==============================================================================

#' Recognized TaxaLikely cache file patterns
#'
#' Per-taxon reference-fetch metadata (\code{fetch_ncbi_reference_sequences()}),
#' per-genus coverage checkpoints (\code{audit_barcode_coverage()}), and the
#' per-accession FASTA store added by the 2026-09-14 cache policy (P2), which
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
#' whether or not a later call could still hit it. To remove only the files
#' that are provably dead -- generations superseded by a cache-key widening,
#' 45% of the meta store as measured on 2026-09-14 -- use
#' \code{\link{taxalikely_evict_unreachable_cache}()} instead, which leaves
#' every reachable file in place and reports rather than deletes by default.
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


#' Delete only the reference-cache files no call can ever hit again
#'
#' The cache key for \code{fetch_ncbi_reference_sequences()} has been widened
#' four times, each time to fix a real staleness crash: \code{barcode_term},
#' \code{rank_system}, \code{keep_out_of_range}, and the length and date
#' bounds. Every one of those fixes was correct, and every one silently
#' ORPHANED the entire preceding generation rather than replacing it --
#' content-keyed caching without eviction does not replace a cache when the
#' key changes, it doubles it. On the development machine that came to 1,584
#' of 3,517 meta files (45%).
#'
#' This function removes exactly those, and nothing else. Unlike
#' \code{\link{taxalikely_clear_cache}()}, which targets every recognized
#' cache file, a file is targeted here only if the current key construction
#' cannot produce its name for ANY arguments -- a proof rather than a
#' heuristic. Two files differing only in a key VALUE (\code{_l100_600}
#' against \code{_l100_5000}, or two different \code{rank_system} sets, both
#' of which are in live use in this ecosystem) are different QUERIES that a
#' caller may legitimately want both of, and are never targeted.
#'
#' @section Why this one defaults to a dry run:
#' The sibling \code{<pkg>_clear_cache()} functions default to
#' \code{dry_run = FALSE}, because the caller who invokes them has already
#' decided what to delete. This function decides for itself what is dead, so
#' it shows you first. Pass \code{dry_run = FALSE} once the report looks
#' right.
#'
#' @param cache_dir Character. Cache directory to inspect. Defaults to
#'   \code{tools::R_user_dir("TaxaLikely", "cache")}, the same default used
#'   by \code{fetch_ncbi_reference_sequences()}.
#' @param dry_run Logical. If \code{TRUE} (the DEFAULT, unlike the sibling
#'   clear functions), reports what would be removed without removing it.
#' @param max_file_mb Numeric. Files larger than this are reported and left
#'   in place even when \code{dry_run = FALSE}, per the 2026-09-14 policy
#'   decision to auto-evict small metadata \code{.rds} files but to
#'   report-and-confirm before deleting anything large. A meta file is about
#'   1 KB, so this is a structural guard rather than an active filter.
#'   \code{NULL} disables it.
#' @return Invisibly, a data frame of the targeted files (\code{path},
#'   \code{size_mb}, \code{mtime}), possibly zero rows.
#' @seealso [taxalikely_clear_cache()],
#'   [TaxaTools::taxaid_cache_report()]
#' @export
#' @examples
#' \dontrun{
#' taxalikely_evict_unreachable_cache() # report only (the default)
#' taxalikely_evict_unreachable_cache(dry_run = FALSE) # actually remove them
#' }
taxalikely_evict_unreachable_cache <- function(
    cache_dir = tools::R_user_dir("TaxaLikely", "cache"),
    dry_run = TRUE,
    max_file_mb = 5) {
  label <- "taxalikely_evict_unreachable_cache"
  if (!is.character(cache_dir) || length(cache_dir) != 1L) {
    stop(sprintf("%s: 'cache_dir' must be a single character string.", label))
  }
  if (!is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run)) {
    stop(sprintf("%s: 'dry_run' must be TRUE or FALSE.", label))
  }
  if (!is.null(max_file_mb) &&
    (!is.numeric(max_file_mb) || length(max_file_mb) != 1L || is.na(max_file_mb))) {
    stop(sprintf("%s: 'max_file_mb' must be a single number or NULL.", label))
  }

  # Non-recursive and meta-only: the fasta/ store is keyed on accession, not
  # on any of the components this grammar knows about, so nothing here can
  # prove anything about it. Coverage checkpoints (_ckpt.rds) likewise.
  inv <- TaxaTools::list_cache_files(cache_dir, "_meta\\.rds$")
  if (nrow(inv) == 0L) {
    message(sprintf("%s: no reference-cache files found in %s.", label, cache_dir))
    return(invisible(inv))
  }

  dead <- .ref_cache_unreachable(cache_dir)
  n_live <- nrow(inv) - length(dead)
  inv <- inv[inv$path %in% dead, , drop = FALSE]

  if (nrow(inv) == 0L) {
    message(sprintf(
      "%s: nothing unreachable -- all %d reference-cache file(s) can still be hit.",
      label, n_live
    ))
    return(invisible(inv))
  }

  if (!is.null(max_file_mb)) {
    big <- inv$size_mb > max_file_mb
    if (any(big)) {
      message(sprintf(
        "%s: %d unreachable file(s) exceed max_file_mb = %g and are LEFT IN PLACE:",
        label, sum(big), max_file_mb
      ))
      for (b in which(big)) {
        message(sprintf("    %s  (%.1f MB)", basename(inv$path[b]), inv$size_mb[b]))
      }
      inv <- inv[!big, , drop = FALSE]
      if (nrow(inv) == 0L) {
        return(invisible(inv))
      }
    }
  }

  message(sprintf(
    "%s: %d of %d reference-cache file(s) are unreachable (%d still live).",
    label, nrow(inv), nrow(inv) + n_live, n_live
  ))
  TaxaTools::report_and_clear_cache(
    inv,
    label = label, cache_dir = cache_dir, dry_run = dry_run
  )
}
