# install_all.R
# Install every TaxaID package in dependency order, from THIS checkout.
#
# Run from any R session:
#   source("<path to a TaxaID checkout>/ecosystem_docs/install_all.R")
#
# The checkout acted on is the one this file belongs to, not a fixed path, so
# sourcing it from a worktree installs that worktree. Override with
# TAXAID_ROOT when you mean a different one:
#   Sys.setenv(TAXAID_ROOT = "~/My Drive/Rscripts/projects/TaxaID")
#
# It prints the path, branch and commit it is installing before it starts.
# Read that line: an installed package records no commit, so this is the only
# point at which installing the wrong tree is visible.

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
  stop("install_all.R must be sourced by its path (or run with Rscript), ",
       "not pasted into the console.", call. = FALSE)
}
source(file.path(.this_dir, "taxaid_root.R"))

ROOT <- .taxaid_root()
.taxaid_report_root(ROOT, "Installing from")

# ---- install ----------------------------------------------------------------
.install <- function(pkg) {
  message(sprintf("\n=== Installing %s ===", pkg))
  devtools::install(file.path(ROOT, pkg), quiet = FALSE, upgrade = FALSE)
}
for (.pkg in .TAXAID_PKG_ORDER) .install(.pkg)

# ---- verify where they landed ------------------------------------------------
# A bare Rscript outside a project root does not always pick up R_LIBS_USER,
# and the system default library accepts a same-version install without
# erroring -- so check rather than assume.
message("\n=== Installed library and build stamp ===")
for (.pkg in .TAXAID_PKG_ORDER) {
  .lib <- tryCatch(dirname(find.package(.pkg)), error = function(e) "NOT FOUND")
  .built <- tryCatch(packageDescription(.pkg)$Built, error = function(e) NA)
  message(sprintf("  %-12s %-50s %s", .pkg, .lib, .built))
}
message("\n=== All TaxaID packages installed. Restart R before loading. ===")
