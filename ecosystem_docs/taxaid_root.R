# taxaid_root.R
# Resolve which TaxaID checkout a helper script should act on, and say so.
#
# Sourced by install_all.R and load_all.R. Both used to name one checkout
# outright, which is the wrong default for a script that lives INSIDE the
# repository: whichever branch that one checkout happened to be on was what
# got installed, and an installed package records no commit, so a reinstall
# from a stale tree succeeds silently and is invisible afterwards.
#
# Resolution order:
#   1. TAXAID_ROOT, if set (the convention diagnostics/ already uses)
#   2. the repository this script is part of
# and if neither resolves, it stops rather than guessing.

# Where THIS file lives. Captured while it is being sourced: source() exposes
# the path on its own call frame, and that frame is gone by the time any
# function defined here is called, so it cannot be looked up later.
.TAXAID_HELPER_DIR <- local({
  d <- NULL
  for (i in seq_len(sys.nframe())) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) { d <- dirname(normalizePath(of)); break }
  }
  if (is.null(d)) {
    a <- commandArgs(trailingOnly = FALSE)
    m <- grep("^--file=", a, value = TRUE)
    if (length(m)) d <- dirname(normalizePath(sub("^--file=", "", m[[1L]])))
  }
  d
})

.taxaid_root <- function() {
  env <- Sys.getenv("TAXAID_ROOT", unset = "")
  if (nzchar(env)) {
    p <- path.expand(env)
    if (!dir.exists(p)) {
      stop("TAXAID_ROOT is set to '", env, "', which is not a directory.",
           call. = FALSE)
    }
    return(normalizePath(p))
  }
  d <- .TAXAID_HELPER_DIR
  if (!is.null(d)) {
    r <- dirname(d) # ecosystem_docs/ -> repository root
    if (dir.exists(file.path(r, "TaxaTools"))) return(normalizePath(r))
  }
  stop("Cannot tell which TaxaID checkout to use. Either source this script ",
       "by its path inside a checkout, or set TAXAID_ROOT to one, e.g.\n",
       '  Sys.setenv(TAXAID_ROOT = "~/My Drive/Rscripts/projects/TaxaID")',
       call. = FALSE)
}

# What is about to be acted on. An install records no commit, so this message
# is the only place the choice is visible; print it before touching anything.
.taxaid_report_root <- function(root, action = "Acting on") {
  git <- function(...) {
    out <- suppressWarnings(
      tryCatch(system2("git", c("-C", root, ...), stdout = TRUE, stderr = FALSE),
               error = function(e) character(0))
    )
    if (length(out) == 0L) NA_character_ else out[[1L]]
  }
  branch <- git("rev-parse", "--abbrev-ref", "HEAD")
  commit <- git("rev-parse", "--short", "HEAD")
  dirty <- git("status", "--porcelain")
  message(sprintf("%s %s", action, root))
  message(sprintf("  branch %s at %s%s",
                  if (is.na(branch)) "(not a git checkout)" else branch,
                  if (is.na(commit)) "(unknown)" else commit,
                  if (!is.na(dirty) && nzchar(dirty)) "  [UNCOMMITTED CHANGES]" else ""))
  missing <- setdiff(.TAXAID_PKG_ORDER, basename(list.dirs(root, recursive = FALSE)))
  if (length(missing)) {
    stop("Not a complete TaxaID checkout -- missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(root)
}

# Dependency order, stated once so the two scripts cannot drift apart:
#   TaxaTools   foundation, no TaxaID dependencies
#   TaxaFetch, TaxaMatch, TaxaHabitat, TaxaLikely   depend on TaxaTools
#   TaxaExpect  depends on TaxaTools, TaxaFetch, TaxaHabitat
#   TaxaAssign  depends on TaxaTools, TaxaLikely, TaxaExpect
#   TaxaFlag    depends on TaxaTools, TaxaAssign
#   TaxaWizard  no TaxaID dependencies
.TAXAID_PKG_ORDER <- c(
  "TaxaTools",
  "TaxaFetch", "TaxaMatch", "TaxaHabitat", "TaxaLikely",
  "TaxaExpect",
  "TaxaAssign",
  "TaxaFlag",
  "TaxaWizard"
)
