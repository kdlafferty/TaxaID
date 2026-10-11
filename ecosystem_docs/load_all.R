# load_all.R
# devtools::load_all() every TaxaID package from source, in dependency order.
# Faster than install_all.R for iterating on code -- no reinstall, no restart --
# but only touches the current R session (nothing is written to the library).
#
# Run from any R session:
#   source("<path to a TaxaID checkout>/ecosystem_docs/load_all.R")
#
# The checkout acted on is the one this file belongs to, not a fixed path, so
# sourcing it from a worktree loads that worktree. Override with TAXAID_ROOT
# when you mean a different one. It prints the path, branch and commit first.

# ---- bootstrap: find this file, then the shared root resolver ----------------
.this_dir <- local({
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
if (is.null(.this_dir)) {
  stop("load_all.R must be sourced by its path (or run with Rscript), ",
       "not pasted into the console.", call. = FALSE)
}
source(file.path(.this_dir, "taxaid_root.R"))

ROOT <- .taxaid_root()
.taxaid_report_root(ROOT, "Loading from")

.load <- function(pkg) {
  path <- file.path(ROOT, pkg)
  message(sprintf("\n=== Loading %s ===", pkg))
  devtools::load_all(path, quiet = FALSE)
}

for (.pkg in .TAXAID_PKG_ORDER) .load(.pkg)

message("\n=== All TaxaID packages load_all()'d from source. ===")
