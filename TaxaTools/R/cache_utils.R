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
#' @param recursive Logical. Descend into subdirectories? Default
#'   \code{FALSE}. Pass \code{TRUE} for a store that keeps part of itself in
#'   a subdirectory -- TaxaLikely's per-accession \code{fasta/} cache is one
#'   example; without it, files inside that subdirectory are invisible to
#'   \code{taxalikely_clear_cache()}. Patterns are still matched against the
#'   BASENAME, so a recursive scan needs a pattern that identifies the file,
#'   not its directory.
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
list_cache_files <- function(cache_dir, patterns, recursive = FALSE) {
  if (!is.character(cache_dir) || length(cache_dir) != 1L) {
    stop("list_cache_files: 'cache_dir' must be a single character string.")
  }
  if (!is.character(patterns) || length(patterns) == 0L) {
    stop("list_cache_files: 'patterns' must be a non-empty character vector.")
  }
  if (!is.logical(recursive) || length(recursive) != 1L || is.na(recursive)) {
    stop("list_cache_files: 'recursive' must be TRUE or FALSE.")
  }

  empty <- data.frame(
    path = character(0), size_mb = numeric(0),
    mtime = as.POSIXct(character(0)), stringsAsFactors = FALSE
  )

  files <- list.files(cache_dir, full.names = TRUE, recursive = recursive)
  if (length(files) == 0L) {
    return(empty)
  }
  files <- files[!dir.exists(files)]
  if (length(files) == 0L) {
    return(empty)
  }

  keep <- Reduce(`|`, lapply(patterns, function(p) grepl(p, basename(files))))
  files <- files[keep]
  if (length(files) == 0L) {
    return(empty)
  }

  info <- file.info(files)
  data.frame(
    path = files,
    size_mb = info$size / 1024^2,
    mtime = info$mtime,
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


#' Is a cache file usable, given the inputs it derives from?
#'
#' A cache gate that tests only \code{file.exists()} silently serves stale
#' results. This is the ecosystem's staleness primitive: a cache is usable
#' only if it exists AND is not older than any of the artifacts it was
#' derived from. Every package file that takes a \code{cache_dir} argument
#' shares this one implementation.
#'
#' @section When \code{inputs} applies:
#' Declare \code{inputs} whenever a cache derives from a file the caller
#' itself writes -- a checkpoint, a bounding box, an upstream \code{.rds}.
#' That is the case this function detects. It does NOT help for a cache
#' whose upstream is a remote service (an NCBI or GBIF query has no local
#' mtime to compare against); that staleness axis is time, and the policy
#' for it is to report the cache's age at load rather than expire it
#' silently.
#'
#' @param path Character. Path to the candidate cache file.
#' @param inputs Character vector or \code{NULL}. Paths this cache was
#'   derived FROM. Missing and \code{NA} entries are ignored, so a caller
#'   can pass an optional upstream without branching. If any surviving
#'   input is newer than \code{path}, the cache is rejected.
#' @return \code{TRUE} if \code{path} exists and no declared input is newer;
#'   \code{FALSE} otherwise. Rejection emits a message naming the culprit.
#' @export
#' @examples
#' up <- tempfile()
#' writeLines("upstream", up)
#' cached <- tempfile()
#' writeLines("derived", cached)
#' cache_ok(cached, inputs = up) # TRUE -- cache is newer
#' cache_ok(tempfile()) # FALSE -- does not exist
cache_ok <- function(path, inputs = NULL) {
  if (!file.exists(path)) {
    return(FALSE)
  }
  if (is.null(inputs)) {
    return(TRUE)
  }
  inputs <- inputs[!is.na(inputs)]
  inputs <- inputs[file.exists(inputs)]
  if (length(inputs) > 0) {
    newer <- inputs[file.mtime(inputs) > file.mtime(path)]
    if (length(newer) > 0) {
      message(sprintf(
        "  STALE CACHE: %s predates %s -- regenerating.",
        basename(path), paste(basename(newer), collapse = ", ")
      ))
      return(FALSE)
    }
  }
  TRUE
}


#' Shorten a label to fit the report column, keeping the distinctive tail
#' @noRd
.trunc_label <- function(x, width) {
  ifelse(nchar(x) <= width, x, paste0("~", substr(x, nchar(x) - width + 2L, nchar(x))))
}

#' Report every TaxaID cache on this machine
#'
#' Each package has its own \code{<pkg>_clear_cache()} function, but none of
#' them shows the whole picture -- a handful of large GBIF zip files can
#' dominate total cache size while every other cache file combined stays
#' small, and that is invisible without an ecosystem-level view. This
#' function is that view: it reports, and never deletes.
#'
#' Caches default to \code{tools::R_user_dir("<pkg>", "cache")}, a hidden
#' per-user directory outside the project, so the sizes here are usually
#' invisible from the analysis they belong to. Project-local cache
#' directories (the \code{file.path(OUT_DIR, ...)} convention the workflows
#' use) are not discoverable automatically -- pass them via
#' \code{extra_dirs}.
#'
#' Counts files recursively, so nested stores such as TaxaLikely's
#' \code{fasta/} subdirectory are included.
#'
#' @section Deliberately not a clear function:
#' Two of these caches do not share one shape. The file-per-key caches
#' (TaxaFetch, TaxaFlag, TaxaHabitat, TaxaLikely) are served by
#' \code{report_and_clear_cache()}. TaxaMatch's is row-level and TTL'd --
#' a few files each holding many entries with their own lifetimes -- so
#' deleting at file granularity would discard live rows. That is why
#' TaxaMatch has no \code{clear_cache()} function, and why this one only
#' reports. See \code{list_cache_files()}'s note on cache shapes.
#'
#' @param extra_dirs Character vector of additional cache directories to
#'   include -- typically the project-local ones a workflow passes as
#'   \code{cache_dir}. Non-existent paths are reported as missing rather
#'   than dropped, so a typo is visible.
#' @param warn_gb Numeric. Directories at or above this size are flagged in
#'   the printed output. Default 1. Set \code{NULL} to disable flagging.
#' @return Invisibly, a data frame with one row per directory:
#'   \code{cache}, \code{path}, \code{exists}, \code{n_files},
#'   \code{size_mb}, \code{oldest}, \code{newest}.
#'
#'   \code{size_mb} is APPARENT size (sum of file bytes). A cache of many
#'   tiny files occupies substantially more than that on disk, because each
#'   file takes at least one filesystem block -- TaxaLikely's per-taxon and
#'   per-accession stores are thousands of ~1 KB files, so their real
#'   footprint is roughly \code{n_files} x block size. Read \code{n_files}
#'   alongside \code{size_mb}; the printed output flags stores where the two
#'   diverge.
#' @seealso [report_and_clear_cache()], [list_cache_files()], [cache_ok()]
#' @export
#' @examples
#' \dontrun{
#' taxaid_cache_report()
#' taxaid_cache_report(extra_dirs = file.path(OUT_DIR, "cache_gbif_global"))
#' }
taxaid_cache_report <- function(extra_dirs = NULL, warn_gb = 1) {
  if (!is.null(extra_dirs) && !is.character(extra_dirs)) {
    stop("taxaid_cache_report: 'extra_dirs' must be a character vector or NULL.")
  }
  if (!is.null(warn_gb) && (!is.numeric(warn_gb) || length(warn_gb) != 1L)) {
    stop("taxaid_cache_report: 'warn_gb' must be a single number or NULL.")
  }

  pkgs <- c(
    "TaxaFetch", "TaxaFlag", "TaxaHabitat",
    "TaxaLikely", "TaxaMatch", "TaxaTools"
  )
  dirs <- vapply(pkgs, function(p) tools::R_user_dir(p, "cache"), character(1L))
  labels <- pkgs

  if (length(extra_dirs) > 0L) {
    dirs <- c(dirs, extra_dirs)
    labels <- c(labels, basename(extra_dirs))
  }

  one <- function(d) {
    if (!dir.exists(d)) {
      return(data.frame(
        exists = FALSE, n_files = 0L, size_mb = 0,
        oldest = as.POSIXct(NA), newest = as.POSIXct(NA),
        stringsAsFactors = FALSE
      ))
    }
    f <- list.files(d, recursive = TRUE, full.names = TRUE, all.files = FALSE)
    if (length(f) == 0L) {
      return(data.frame(
        exists = TRUE, n_files = 0L, size_mb = 0,
        oldest = as.POSIXct(NA), newest = as.POSIXct(NA),
        stringsAsFactors = FALSE
      ))
    }
    info <- file.info(f)
    data.frame(
      exists = TRUE, n_files = length(f),
      size_mb = sum(info$size, na.rm = TRUE) / 1024^2,
      oldest = min(info$mtime, na.rm = TRUE),
      newest = max(info$mtime, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }

  parts <- do.call(rbind, lapply(dirs, one))
  out <- cbind(
    data.frame(cache = labels, path = unname(dirs), stringsAsFactors = FALSE),
    parts
  )
  out <- out[order(-out$size_mb), , drop = FALSE]
  rownames(out) <- NULL

  message("TaxaID cache report")
  message(strrep("-", 66))
  for (i in seq_len(nrow(out))) {
    r <- out[i, ]
    if (!r$exists) {
      message(sprintf("  %-20s  (no cache directory)", .trunc_label(r$cache, 20L)))
      next
    }
    if (r$n_files == 0L) {
      message(sprintf("  %-20s  empty", .trunc_label(r$cache, 20L)))
      next
    }
    flag <- if (!is.null(warn_gb) && r$size_mb >= warn_gb * 1024) {
      "  <-- LARGE"
    } else if (r$n_files >= 1000L && r$size_mb < r$n_files * 0.004) {
      # Many tiny files: apparent size badly understates disk footprint.
      "  <-- many small files"
    } else {
      ""
    }
    message(sprintf(
      "  %-20s  %7.1f MB  %5d file(s)  %s to %s%s",
      .trunc_label(r$cache, 20L), r$size_mb, r$n_files,
      format(r$oldest, "%Y-%m-%d"), format(r$newest, "%Y-%m-%d"), flag
    ))
  }
  message(strrep("-", 66))
  message(sprintf(
    "  %-20s  %7.1f MB  %5d file(s)",
    "TOTAL", sum(out$size_mb), sum(out$n_files)
  ))
  message(
    "Reporting only -- nothing was deleted. Per-package pruning: ",
    "taxafetch_clear_cache(), taxaflag_clear_cache(), ",
    "taxahabitat_clear_cache(), taxalikely_clear_cache(), ",
    "taxatools_clear_cache(). TaxaMatch's cache is row-level and TTL'd, so ",
    "it has no file-level clear function by design."
  )

  invisible(out)
}
