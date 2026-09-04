# ==============================================================================
# cache_utils.R
# TaxaTools -- shared engine behind every downstream package's own
# <pkg>_clear_cache()-style helper for a persistent, file-per-key on-disk
# cache (e.g. TaxaFetch::taxafetch_clear_cache(),
# TaxaLikely::taxalikely_clear_cache()).
#
# This engine fits any cache shaped as "a directory holding many small
# files, each deterministically named by its own query/key, with no
# built-in expiration." It deliberately does NOT fit a cache shaped as "one
# or a few files, each holding many logical entries with their own
# lifetimes" (e.g. TaxaMatch's row-level, TTL'd reference-accession cache)
# -- that shape needs entry-level (not file-level) eviction and is handled
# by its own package-specific mechanism instead.
# ==============================================================================

#' List files in a directory matching cache-file patterns
#'
#' Generic building block for a package's own \code{<pkg>_clear_cache()}
#' helper: scans \code{cache_dir} and returns every file whose basename
#' matches any of \code{patterns}, with size and modification time. See
#' \code{TaxaFetch::taxafetch_clear_cache()}/
#' \code{TaxaLikely::taxalikely_clear_cache()} for worked examples of a
#' downstream package building on this.
#'
#' @param cache_dir Character. Directory to scan.
#' @param patterns Character vector of regular expressions matched against
#'   each file's basename (via \code{grepl()}); a file matching ANY pattern
#'   is included.
#' @return A data frame with columns \code{path}, \code{size_mb},
#'   \code{mtime} (zero rows if \code{cache_dir} has no matching files or
#'   does not exist).
#' @export
#' @examples
#' d <- tempfile()
#' dir.create(d)
#' writeLines("x", file.path(d, "foo_meta.rds"))
#' writeLines("x", file.path(d, "unrelated.txt"))
#' list_cache_files(d, "_meta\\.rds$")
list_cache_files <- function(cache_dir, patterns) {
  if (!is.character(cache_dir) || length(cache_dir) != 1L) {
    stop("list_cache_files: 'cache_dir' must be a single character string.")
  }
  if (!is.character(patterns) || length(patterns) == 0L) {
    stop("list_cache_files: 'patterns' must be a non-empty character vector.")
  }

  empty <- data.frame(
    path = character(0), size_mb = numeric(0),
    mtime = as.POSIXct(character(0)), stringsAsFactors = FALSE
  )

  files <- list.files(cache_dir, full.names = TRUE)
  if (length(files) == 0L) return(empty)

  keep <- Reduce(`|`, lapply(patterns, function(p) grepl(p, basename(files))))
  files <- files[keep]
  if (length(files) == 0L) return(empty)

  info <- file.info(files)
  data.frame(
    path    = files,
    size_mb = info$size / 1024^2,
    mtime   = info$mtime,
    stringsAsFactors = FALSE
  )
}


#' Report and optionally delete a set of cache files
#'
#' Shared "apply an age filter, print a summary, delete or dry-run report"
#' engine behind every \code{<pkg>_clear_cache()}-style helper in this
#' ecosystem. A caller builds its own inventory first -- typically via
#' \code{list_cache_files()}, with any package-specific pre-filtering (e.g.
#' TaxaFetch's own orphan detection) already applied -- and hands it to this
#' function to do the rest.
#'
#' @param inv A data frame with \code{path}, \code{size_mb}, \code{mtime}
#'   columns, as returned by \code{list_cache_files()}.
#' @param label Character. Name shown in messages -- typically the calling
#'   \code{<pkg>_clear_cache()} function's own name, so a user sees which
#'   function actually printed a given message.
#' @param cache_dir Character. Shown in messages only; \code{inv} is used
#'   as-is and is not re-scanned.
#' @param older_than_days Numeric or \code{NULL}. When supplied, only rows
#'   of \code{inv} older than this many days (by \code{mtime}) are
#'   targeted. \code{NULL} (default) targets every row of \code{inv}.
#' @param dry_run Logical. If \code{TRUE}, reports what would be removed
#'   without removing anything. Default \code{FALSE}.
#' @return Invisibly, the (possibly \code{older_than_days}-filtered) subset
#'   of \code{inv} that was targeted.
#' @export
#' @examples
#' \dontrun{
#' inv <- list_cache_files(cache_dir, c("\\.zip$", "_meta\\.rds$"))
#' report_and_clear_cache(inv, "my_pkg_clear_cache", cache_dir, dry_run = TRUE)
#' }
report_and_clear_cache <- function(inv, label, cache_dir,
                                    older_than_days = NULL, dry_run = FALSE) {
  if (!is.data.frame(inv) || !all(c("path", "size_mb", "mtime") %in% names(inv))) {
    stop("report_and_clear_cache: 'inv' must be a data frame with 'path', 'size_mb', 'mtime' columns.")
  }
  if (!is.character(label) || length(label) != 1L) {
    stop("report_and_clear_cache: 'label' must be a single character string.")
  }
  if (!is.character(cache_dir) || length(cache_dir) != 1L) {
    stop("report_and_clear_cache: 'cache_dir' must be a single character string.")
  }
  if (!is.null(older_than_days)) {
    if (!is.numeric(older_than_days) || length(older_than_days) != 1L ||
        is.na(older_than_days) || older_than_days < 0) {
      stop(sprintf("%s: 'older_than_days' must be a single non-negative number or NULL.", label))
    }
  }
  if (!is.logical(dry_run) || length(dry_run) != 1L || is.na(dry_run)) {
    stop(sprintf("%s: 'dry_run' must be TRUE or FALSE.", label))
  }

  if (nrow(inv) == 0L) {
    message(sprintf("%s: no cache files found in %s.", label, cache_dir))
    return(invisible(inv))
  }

  if (!is.null(older_than_days)) {
    cutoff <- Sys.time() - older_than_days * 86400
    inv <- inv[inv$mtime < cutoff, , drop = FALSE]
  }

  if (nrow(inv) == 0L) {
    message(sprintf("%s: no cache files match the given criteria.", label))
    return(invisible(inv))
  }

  total_mb <- round(sum(inv$size_mb), 1)
  message(sprintf(
    "%s: %d file(s), %.1f MB %s in %s.",
    label, nrow(inv), total_mb,
    if (dry_run) "would be removed" else "removed",
    cache_dir
  ))

  if (!dry_run) {
    removed <- file.remove(inv$path)
    if (!all(removed)) {
      warning(sprintf("%s: failed to remove %d file(s).", label, sum(!removed)))
    }
  }

  invisible(inv)
}
