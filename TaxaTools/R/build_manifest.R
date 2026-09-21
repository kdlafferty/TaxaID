# ==============================================================================
# Build manifest: what code a run actually used
# ==============================================================================
#
# The TaxaID packages all sit at version 0.1.0 and are reinstalled constantly
# during development, so a version string cannot tell you whether the library a
# run used is the library you think it used. Two runs a week apart can report
# identical versions and have executed materially different code -- which is
# how a habitat-realm bug, an abundance auto-detector and a stale decisions
# file all persisted unnoticed in this ecosystem.
#
# These functions record a HASH OF THE INSTALLED CODE per package, so drift is
# detectable at the point of use rather than by memory.

.taxaid_packages <- c(
  "TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaExpect",
  "TaxaAssign", "TaxaMatch", "TaxaLikely", "TaxaFlag", "TaxaWizard"
)

#' Hash a package's installed code
#'
#' Deparses every function in the namespace (exported and internal) and hashes
#' the result. Deliberately code-based rather than build-based: a harmless
#' reinstall of identical source leaves this unchanged, while a one-line edit
#' moves it. A `Built` timestamp does the opposite and would cry wolf on every
#' rebuild, which is how a check gets switched off.
#'
#' Internals are included because a behaviour change need not touch an exported
#' signature -- a column-inference bug can live entirely inside an internal
#' helper.
#'
#' @param pkg Character package name.
#' @return A 32-character md5 string, or `NA_character_` if not installed.
#' @noRd
.taxaid_code_hash <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    return(NA_character_)
  }
  ns <- asNamespace(pkg)
  nms <- sort(ls(ns, all.names = TRUE))
  txt <- vapply(nms, function(n) {
    v <- tryCatch(get(n, envir = ns), error = function(e) NULL)
    if (is.function(v)) {
      paste0(n, " <<>> ", paste(deparse(v), collapse = "\n"))
    } else {
      ""
    }
  }, character(1L))
  txt <- txt[nzchar(txt)]
  if (length(txt) == 0L) {
    return(NA_character_)
  }
  tf <- tempfile()
  on.exit(unlink(tf), add = TRUE)
  writeLines(txt, tf, useBytes = TRUE)
  unname(tools::md5sum(tf))
}

#' Record Which TaxaID Code a Run Is Using
#'
#' Captures, for each TaxaID package, its version, `Built` timestamp and a hash
#' of its installed code. Save it beside a run's outputs and every result
#' becomes traceable to the exact build that produced it.
#'
#' @param packages Character vector of package names. Defaults to the nine
#'   TaxaID packages.
#' @return A data frame with columns `package`, `version`, `built`,
#'   `code_hash`, `installed`. Packages that are NOT installed appear with
#'   `installed = FALSE` rather than being dropped -- absence has to be
#'   representable for [check_taxaid_manifest()] to report it.
#' @seealso [write_taxaid_manifest()], [check_taxaid_manifest()]
#' @export
#' @examples
#' \dontrun{
#' m <- taxaid_build_manifest()
#' saveRDS(m, file.path(OUT_DIR, paste0(OUT_PREFIX, "_build_manifest.rds")))
#' }
taxaid_build_manifest <- function(packages = NULL) {
  packages <- packages %||% .taxaid_packages
  if (!is.character(packages) || length(packages) == 0L || anyNA(packages)) {
    stop("taxaid_build_manifest: 'packages' must be a non-empty character vector.")
  }
  inst <- vapply(packages, function(p) requireNamespace(p, quietly = TRUE), logical(1L))
  data.frame(
    package = packages,
    version = vapply(seq_along(packages), function(i) {
      if (inst[[i]]) as.character(utils::packageVersion(packages[[i]])) else NA_character_
    }, character(1L)),
    built = vapply(seq_along(packages), function(i) {
      if (!inst[[i]]) {
        return(NA_character_)
      }
      b <- utils::packageDescription(packages[[i]])$Built
      if (is.null(b)) NA_character_ else as.character(b)
    }, character(1L)),
    code_hash = vapply(packages, .taxaid_code_hash, character(1L)),
    installed = unname(inst),
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

#' Write a TaxaID Build Manifest
#'
#' @param path File path to write (`.rds`).
#' @param packages Passed to [taxaid_build_manifest()].
#' @return The manifest, invisibly.
#' @seealso [check_taxaid_manifest()]
#' @export
#' @examples
#' \dontrun{
#' # In a workflow preamble: record the current library once, then check it on
#' # every later run.
#' manifest <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_build_manifest.rds"))
#' if (!file.exists(manifest)) {
#'   write_taxaid_manifest(manifest)
#' } else {
#'   check_taxaid_manifest(manifest)
#' }
#' }
write_taxaid_manifest <- function(path, packages = NULL) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("write_taxaid_manifest: 'path' must be a single file path.")
  }
  m <- taxaid_build_manifest(packages)
  saveRDS(m, path)
  message(sprintf(
    "write_taxaid_manifest: recorded %d package(s) (%d installed) to %s",
    nrow(m), sum(m$installed), basename(path)
  ))
  invisible(m)
}

#' Check the Installed TaxaID Code Against a Recorded Manifest
#'
#' Compares the library this session is using against a manifest written by
#' [write_taxaid_manifest()], and by default **errors** on any difference. Put
#' it in a workflow preamble so drift stops a run at the top rather than
#' producing results nobody can attribute afterwards.
#'
#' @section What it reports, and why absence comes first:
#' \describe{
#'   \item{MISSING}{In the manifest, not installed now. Reported first and
#'     deliberately: a checker that only compares what it finds on BOTH sides
#'     cannot report what is absent, and a package that has silently vanished
#'     from the library is the most dangerous of the three -- calls to it fail
#'     late, or resolve to a different namespace.}
#'   \item{CHANGED}{Installed, but the code hash differs -- someone reinstalled
#'     between the manifest and this run.}
#'   \item{EXTRA}{Installed now, absent from the manifest; usually a manifest
#'     written before a package existed.}
#' }
#' Version and `Built` differences are shown but never fail on their own:
#' rebuilding identical source moves `Built` and changes nothing that matters,
#' and every TaxaID package sits at 0.1.0 so the version is silent by
#' construction. The code hash is the signal.
#'
#' @param path Path to a manifest written by [write_taxaid_manifest()].
#' @param packages Restrict the comparison. Default: every package named in the
#'   manifest or in the standard TaxaID set.
#' @param on_mismatch One of `"error"` (default), `"warning"`, `"message"`,
#'   `"silent"`.
#' @return Invisibly, a list with `ok`, `missing`, `changed`, `extra` and
#'   `manifest` (the freshly built one).
#' @seealso [write_taxaid_manifest()]
#' @export
#' @examples
#' \dontrun{
#' check_taxaid_manifest(file.path(OUT_DIR, "build_manifest.rds"))
#' }
check_taxaid_manifest <- function(path,
                                  packages = NULL,
                                  on_mismatch = c("error", "warning", "message", "silent")) {
  on_mismatch <- match.arg(on_mismatch)
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("check_taxaid_manifest: 'path' must be a single file path.")
  }
  if (!file.exists(path)) {
    stop("check_taxaid_manifest: manifest not found: ", path)
  }
  old <- readRDS(path)
  if (!is.data.frame(old) || !all(c("package", "code_hash") %in% names(old))) {
    stop("check_taxaid_manifest: '", basename(path), "' is not a build manifest.")
  }
  if (!"installed" %in% names(old)) {
    old$installed <- !is.na(old$code_hash)
  }

  pkgs <- packages %||% union(old$package, .taxaid_packages)
  now <- taxaid_build_manifest(pkgs)

  idx <- match(pkgs, old$package)
  was_installed <- !is.na(idx) & old$installed[idx] %in% TRUE
  is_installed <- now$installed
  old_hash <- old$code_hash[idx]
  old_built <- old$built[idx]

  missing <- pkgs[was_installed & !is_installed]
  extra <- pkgs[!was_installed & is_installed]
  both <- was_installed & is_installed
  changed <- pkgs[both & !is.na(old_hash) & old_hash != now$code_hash]

  ok <- length(missing) == 0L && length(changed) == 0L && length(extra) == 0L

  if (!ok) {
    parts <- character(0L)
    if (length(missing) > 0L) {
      parts <- c(parts, sprintf(
        "  MISSING (in the manifest, not installed now): %s",
        paste(missing, collapse = ", ")
      ))
    }
    if (length(changed) > 0L) {
      det <- vapply(changed, function(p) {
        i <- match(p, pkgs)
        sprintf("      %s: built %s -> %s", p, old_built[i], now$built[i])
      }, character(1L))
      parts <- c(parts, sprintf(
        "  CHANGED (installed code differs from the manifest): %s\n%s",
        paste(changed, collapse = ", "), paste(det, collapse = "\n")
      ))
    }
    if (length(extra) > 0L) {
      parts <- c(parts, sprintf(
        "  EXTRA (installed now, not in the manifest): %s",
        paste(extra, collapse = ", ")
      ))
    }
    msg <- sprintf(
      paste0(
        "check_taxaid_manifest: the installed TaxaID code does not match %s.\n%s\n",
        "  Results from this run would not be attributable to the recorded build.\n",
        "  Reinstall to match, or rewrite the manifest with write_taxaid_manifest()",
        " if the new build is the intended one."
      ),
      basename(path), paste(parts, collapse = "\n")
    )
    switch(on_mismatch,
      error = stop(msg, call. = FALSE),
      warning = warning(msg, call. = FALSE),
      message = message(msg),
      silent = NULL
    )
  } else if (!identical(on_mismatch, "silent")) {
    message(sprintf(
      "check_taxaid_manifest: %d package(s) match %s.",
      sum(both), basename(path)
    ))
  }

  invisible(list(
    ok = ok, missing = missing, changed = changed, extra = extra, manifest = now
  ))
}
