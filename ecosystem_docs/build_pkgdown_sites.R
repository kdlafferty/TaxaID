# Build local pkgdown reference sites for the 8 core TaxaID packages.
#
# pkgdown's own package_mds() unconditionally renders every top-level *.md
# file in a package's source directory as a public page, except a small
# hardcoded exclusion list (README.md/NEWS.md/LICENSE(.md)) -- there is no
# _pkgdown.yml option to exclude an arbitrary extra file like CLAUDE.md
# (this ecosystem's per-package internal dev-notes log, never meant to be
# published). So each site is built from a throwaway temp copy of the
# package with CLAUDE.md removed, never from the real source tree -- the
# real CLAUDE.md is never touched, and there is nothing to remember to
# restore afterward.
#
# Destination is local-only (pkgdown_sites/, gitignored): this project is
# migrating to a USGS GitLab repo for publication, so the final hosting
# URL/scheme isn't decided yet. Run from the TaxaID project root:
#   Rscript ecosystem_docs/build_pkgdown_sites.R
# or a single package:
#   Rscript ecosystem_docs/build_pkgdown_sites.R TaxaLikely

root <- normalizePath(".")
all_packages <- c(
  "TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
  "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag"
)

args <- commandArgs(trailingOnly = TRUE)
packages <- if (length(args) > 0) args else all_packages
stopifnot(all(packages %in% all_packages))

dest_root <- file.path(root, "pkgdown_sites")
dir.create(dest_root, showWarnings = FALSE)

results <- list()

for (pkg in packages) {
  message("\n==== ", pkg, " ====")

  src <- file.path(root, pkg)
  tmp_parent <- file.path(tempdir(), "pkgdown_build")
  dir.create(tmp_parent, showWarnings = FALSE)
  tmp_pkg <- file.path(tmp_parent, pkg)
  unlink(tmp_pkg, recursive = TRUE, force = TRUE)

  file.copy(src, tmp_parent, recursive = TRUE)
  claude_md <- file.path(tmp_pkg, "CLAUDE.md")
  if (file.exists(claude_md)) file.remove(claude_md)

  dest <- file.path(dest_root, pkg)

  ok <- tryCatch({
    pkgdown::build_site(
      pkg = tmp_pkg,
      override = list(destination = dest),
      install = FALSE,
      preview = FALSE
    )
    TRUE
  }, error = function(e) {
    message("BUILD FAILED for ", pkg, ": ", conditionMessage(e))
    FALSE
  })

  unlink(tmp_pkg, recursive = TRUE, force = TRUE)
  results[[pkg]] <- ok
}

message("\n==== Summary ====")
for (pkg in names(results)) {
  message(sprintf("%-12s %s", pkg, if (results[[pkg]]) "OK" else "FAILED"))
}
