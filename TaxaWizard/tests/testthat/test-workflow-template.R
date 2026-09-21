# Tests for inst/TaxaID_Workflow_Template.R -- the repo's single-site workflow
# template, GENERATED from the workflow graph's snippets by
# TaxaWizard/inst/tools/build_workflow_template.R.
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
  gen <- file.path(root, "TaxaWizard", "inst", "tools", "build_workflow_template.R")
  committed <- file.path(root, "inst", "TaxaID_Workflow_Template.R")
  skip_if(!file.exists(committed), "template not found")
  # Deliberately no skip_on_cran(): these packages are never submitted to
  # CRAN, and this is the file's strongest guard -- a bare testthat::test_file()
  # run (no NOT_CRAN env var set) would otherwise silently skip it instead of
  # running or failing, exactly the failure mode this test exists to prevent.
  if (!file.exists(gen)) {
    fail(paste0(
      "generator script not found at ", gen, " -- it ships inside ",
      "TaxaWizard/inst/tools/ and its absence here (with a repo root and a ",
      "committed template both found) means something moved it or the ",
      "package tree is broken, not that the check should be skipped."
    ))
  }

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
  # A guard that cannot run must fail loudly, not disappear as a skip: this
  # is the same class of failure as the generator erroring outright (e.g. on
  # "Placeholders used by a snippet but absent from CONFIG/DATAFLOW"), and a
  # silent skip here would have hidden exactly that error the last time it
  # happened.
  if (!file.exists(out)) {
    fail(paste("generator could not run in a subprocess:", paste(utils::tail(res, 3), collapse = " | ")))
  } else {
    expect_identical(
      paste(readLines(committed, warn = FALSE), collapse = "\n"),
      paste(readLines(out, warn = FALSE), collapse = "\n"),
      info = "template is stale -- run: Rscript TaxaWizard/inst/tools/build_workflow_template.R"
    )
  }
})

test_that("every {{placeholder}} used by a CANONICAL_PATH snippet is declared in CONFIG or DATAFLOW", {
  # This is the generator's own build-time guard ("Placeholders used by a
  # snippet but absent from CONFIG/DATAFLOW"), pinned as a real testthat
  # assertion too, so drift is caught at `devtools::test()` time even if
  # nobody happens to run the generator script by hand.
  #
  # Scoped to CANONICAL_PATH deliberately, not every snippet the graph has:
  # CONFIG/DATAFLOW exist ONLY to deterministically fill the one canonical
  # single-site template this generator produces. Every OTHER snippet (used
  # by the interactive conversational assistant for a different route) has
  # its `{{placeholder}}` tokens filled a completely different way -- shown
  # to the LLM as reference text (see graph.R's "{{SNIPPETS}}" prompt-pack
  # substitution) for it to write real values into during the conversation,
  # never substituted by this package's own R code at all. Asserting
  # CONFIG/DATAFLOW coverage over EVERY snippet would be checking an
  # invariant that was never true by design (confirmed: dozens of
  # legitimately-uncovered placeholders in birdnet_to_match.R,
  # run_to_report.R, and others) -- not a drift to catch.
  root <- TaxaWizard:::.pack_find_repo_root()
  skip_if(is.null(root), "repo root not found")
  gen <- file.path(root, "TaxaWizard", "inst", "tools", "build_workflow_template.R")
  snippets_dir <- file.path(root, "TaxaWizard", "inst", "graph", "snippets")
  skip_if(!file.exists(gen) || !dir.exists(snippets_dir), "generator or snippets dir not found")

  # Extract CANONICAL_PATH/CONFIG/DATAFLOW straight from the generator's own
  # source, without running its graph-walking/file-writing side effects:
  # only the top-level assignment expressions that define them are
  # evaluated.
  gen_exprs <- parse(gen, keep.source = FALSE)
  env <- new.env()
  for (e in as.list(gen_exprs)) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) &&
        is.name(e[[2]]) &&
        as.character(e[[2]]) %in% c("CONFIG", "DATAFLOW", "CANONICAL_PATH")) {
      eval(e, envir = env)
    }
  }
  declared <- union(names(env$CONFIG), names(env$DATAFLOW))
  expect_gt(length(declared), 0L) # sanity: the extraction above actually worked
  expect_gt(length(env$CANONICAL_PATH), 0L)

  snippet_files <- file.path(snippets_dir, paste0(env$CANONICAL_PATH, ".R"))
  expect_true(all(file.exists(snippet_files)))

  missing_by_file <- list()
  for (f in snippet_files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    ph <- unique(gsub("[{}]", "", unlist(
      regmatches(txt, gregexpr("\\{\\{[a-zA-Z_0-9]+\\}\\}", txt))
    )))
    missing <- setdiff(ph, declared)
    if (length(missing) > 0L) {
      missing_by_file[[basename(f)]] <- missing
    }
  }

  expect_equal(missing_by_file, list(),
    info = paste(
      "CANONICAL_PATH snippet placeholder(s) missing from CONFIG/DATAFLOW:",
      paste(sprintf(
        "%s: %s", names(missing_by_file),
        vapply(missing_by_file, paste, "", collapse = ", ")
      ), collapse = "; ")
    )
  )
})
