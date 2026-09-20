# Tests for inst/TaxaID_Workflow_Template.R -- the repo's single-site workflow
# template, GENERATED from the workflow graph's snippets by
# diagnostics/build_workflow_template.R.
#
# WHY THESE EXIST. TaxaID has had two hand-written workflow templates and both
# sat unrunnable for months while looking maintained: the package-level one
# called seven functions archived in 2026-09-09 (retired 2026-09-15), and the
# canonical one fell behind on four subsystems (repaired 2026-09-17). Nothing
# compared either to the code it claimed to demonstrate. These tests are that
# comparison.

.tmpl_path <- function() {
  root <- TaxaWizard:::.pack_find_repo_root()
  if (is.null(root)) return(NULL)
  f <- file.path(root, "inst", "TaxaID_Workflow_Template.R")
  if (!file.exists(f)) return(NULL)
  f
}

test_that("the committed template has no unresolved placeholders", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found (expected under R CMD check)")

  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  left <- unique(unlist(regmatches(txt, gregexpr("\\{\\{[a-zA-Z_0-9]+\\}\\}", txt))))
  expect_equal(left, character(0),
               info = paste("unsubstituted placeholders:", paste(left, collapse = ", ")))
})

test_that("the committed template parses", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")
  expect_silent(parse(f, keep.source = FALSE))
})

test_that("every Pkg::fn in the template is a real export", {
  # The failure mode that retired the last template: it called seven functions
  # that no longer existed anywhere.
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")

  reg <- workflow_registry()
  exports <- unlist(lapply(reg, function(p) vapply(p$functions, `[[`, "", "name")))
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  calls <- unique(unlist(regmatches(txt, gregexpr("Taxa[A-Za-z]+::[A-Za-z_.0-9]+", txt))))
  calls <- calls[!grepl("^TaxaWizard::", calls)]
  bad <- calls[!sub(".*::", "", calls) %in% exports]

  expect_equal(bad, character(0),
               info = paste("not exports of the package they name:", paste(bad, collapse = ", ")))
})

test_that("every named argument in the template is a real formal", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")

  reg <- workflow_registry()
  exprs <- parse(f, keep.source = FALSE)
  stale <- character()
  walk <- function(x) {
    if (is.call(x)) {
      head_call <- x[[1]]
      if (is.call(head_call) && identical(head_call[[1]], as.name("::")) &&
          as.character(head_call[[2]]) %in% names(reg)) {
        pkg <- as.character(head_call[[2]]); fn <- as.character(head_call[[3]])
        entry <- Filter(function(z) z$name == fn, reg[[pkg]]$functions)
        if (length(entry)) {
          formals_ok <- vapply(entry[[1]]$params, `[[`, "", "name")
          given <- names(as.list(x))[-1]; given <- given[nzchar(given)]
          if (!"..." %in% formals_ok) {
            d <- setdiff(given, formals_ok)
            if (length(d)) {
              stale <<- c(stale, sprintf("%s::%s(%s)", pkg, fn, paste(d, collapse = ", ")))
            }
          }
        }
      }
      rest <- as.list(x)[-1]
      for (i in seq_along(rest)) {
        if (!identical(rest[[i]], quote(expr = ))) walk(rest[[i]])
      }
    }
  }
  for (e in exprs) walk(e)

  expect_equal(unique(stale), character(0),
               info = paste("arguments absent from the real formals:",
                            paste(unique(stale), collapse = "; ")))
})

test_that("the committed template is what the generator currently produces", {
  # The strongest guard: a snippet change that never reached the template fails
  # here rather than silently making the template wrong. This is what neither
  # previous template had.
  root <- TaxaWizard:::.pack_find_repo_root()
  skip_if(is.null(root), "repo root not found")
  gen <- file.path(root, "diagnostics", "build_workflow_template.R")
  committed <- file.path(root, "inst", "TaxaID_Workflow_Template.R")
  skip_if(!file.exists(gen) || !file.exists(committed), "generator or template not found")
  skip_on_cran()

  out <- tempfile("tmpl_", fileext = ".R")
  on.exit(unlink(out), add = TRUE)
  # Set the variables in THIS process and let the child inherit them.
  # system2(env=) builds an `env VAR=val` prefix without quoting, so a value
  # containing a space -- which every path under "My Drive" does -- breaks the
  # command outright.
  old_env <- Sys.getenv(c("TAXAID_ROOT", "TAXAID_TEMPLATE_OUT"), unset = NA)
  Sys.setenv(TAXAID_ROOT = root, TAXAID_TEMPLATE_OUT = out)
  on.exit({
    for (nm in names(old_env)) {
      if (is.na(old_env[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, stats::setNames(list(old_env[[nm]]), nm))
    }
  }, add = TRUE)

  rscript <- file.path(R.home("bin"), "Rscript")
  res <- suppressWarnings(system2(rscript, shQuote(gen), stdout = TRUE, stderr = TRUE))
  skip_if(!file.exists(out),
          paste("generator could not run in a subprocess:", paste(utils::tail(res, 3), collapse = " | ")))

  expect_identical(
    paste(readLines(committed, warn = FALSE), collapse = "\n"),
    paste(readLines(out, warn = FALSE), collapse = "\n"),
    info = "template is stale -- run: Rscript diagnostics/build_workflow_template.R"
  )
})
