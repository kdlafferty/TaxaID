# Metadata coverage guard (2026-09-15)
#
# TaxaWizard generates workflow code from inst/metadata/*.json. A function
# absent from that metadata is one the generator cannot express -- so a
# generated workflow silently cannot do it.
#
# On 2026-09-15 the metadata was missing 105 of 207 ecosystem exports (51%),
# including every cache-management function and core pipeline steps such as
# calibrate_query_noise(), restore_suppressed_candidates(),
# expand_unreferenced_hypotheses() and get_gbif_occurrences(). It had drifted
# because nothing checked it: the existing structural guard only tests the
# OTHER direction (every function NAMED in a snippet must be a real export),
# which cannot see an omission.
#
# THE CRITERION IS COMPUTED, NOT CURATED. The user's decision was that
# metadata must cover what real workflows actually call. So this test derives
# the requirement from the workflow corpus itself rather than from a
# hand-kept list that would drift in exactly the same way.
#
# Scope note: it scans the IN-REPO corpus only (inst/, each package's
# inst/workflows/, TaxaWizard's own snippets). The production site workflows
# live outside this repository and cannot be a test dependency -- they are not
# present on another machine or under R CMD check. The metadata deliberately
# covers a superset, including functions only the external workflows call.

testthat::test_that("every ecosystem function an in-repo workflow calls has a metadata entry", {
  pkgs <- c("TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
            "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag")
  for (p in pkgs) testthat::skip_if_not_installed(p)
  testthat::skip_if_not_installed("jsonlite")

  md_dir <- system.file("metadata", package = "TaxaWizard")
  testthat::skip_if(!nzchar(md_dir) || !dir.exists(md_dir), "metadata not installed")

  root <- testthat::test_path("..", "..", "..")
  corpus <- c(
    list.files(file.path(root, "inst"), "\\.R$", recursive = TRUE, full.names = TRUE),
    Sys.glob(file.path(root, "Taxa*", "inst", "workflows", "*.R")),
    Sys.glob(file.path(root, "TaxaWizard", "inst", "graph", "snippets", "*.R"))
  )
  testthat::skip_if(length(corpus) == 0, "workflow corpus not available (installed-package run)")

  txt <- paste(unlist(lapply(corpus, function(f)
    tryCatch(readLines(f, warn = FALSE), error = function(e) character(0)))), collapse = "\n")

  missing <- character(0)
  for (p in pkgs) {
    f <- file.path(md_dir, paste0(p, ".json"))
    if (!file.exists(f)) next
    j <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    documented <- vapply(j$functions, function(x) {
      nm <- x[["name"]]
      if (is.null(nm)) NA_character_ else as.character(nm)
    }, character(1))

    exports <- sort(getNamespaceExports(p))
    exports <- exports[!grepl("^%|^\\.", exports)]
    for (fn in setdiff(exports, documented)) {
      # word-boundary call site: `fn(` not preceded by an identifier character
      if (grepl(paste0("(^|[^A-Za-z0-9._])", fn, "\\("), txt)) {
        missing <- c(missing, paste0(p, "::", fn))
      }
    }
  }

  testthat::expect_equal(
    missing, character(0),
    info = paste0(
      "These functions are called by an in-repo workflow but have no TaxaWizard ",
      "metadata entry, so the generator cannot express them:\n  ",
      paste(missing, collapse = "\n  "),
      "\nAdd an entry to TaxaWizard/inst/metadata/<Package>.json."
    )
  )
})
