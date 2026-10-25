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

# Collect every call to `Pkg::fn` (fn in `fns`) in a parsed file, by AST walk.
.template_calls <- function(f, pkg, fns) {
  exprs <- parse(f, keep.source = FALSE)
  found <- list()
  walk <- function(x) {
    if (is.call(x)) {
      h <- x[[1]]
      if (is.call(h) && identical(h[[1]], as.name("::")) &&
          identical(as.character(h[[2]]), pkg) && as.character(h[[3]]) %in% fns) {
        found[[length(found) + 1L]] <<- x
      }
      rest <- as.list(x)[-1]
      for (i in seq_along(rest)) {
        if (!identical(rest[[i]], quote(expr = ))) walk(rest[[i]])
      }
    }
  }
  for (e in exprs) walk(e)
  found
}

test_that("every taxonomy lookup in the template passes input_rank", {
  # A bare name is not a key: without the name's own rank, a coarse-rank name
  # resolves to whichever homonym the backbone returns first (a class-rank
  # name to a flagellate genus). A renamed or unknown argument is caught by the
  # formals test above; an argument the template simply omits is caught here.
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")

  calls <- .template_calls(f, "TaxaTools", c("verify_taxon_names", "fill_higher_ranks"))
  expect_gt(length(calls), 0L)  # sanity: the walk found the calls it guards
  missing <- vapply(calls, function(cl) {
    !"input_rank" %in% names(as.list(cl))
  }, logical(1))
  expect_false(any(missing),
               info = paste(sum(missing), "taxonomy lookup call(s) without input_rank"))
  # The retired fill_higher_ranks(ranks =) spelling is fill_ranks now.
  old <- vapply(calls, function(cl) "ranks" %in% names(as.list(cl)), logical(1))
  expect_false(any(old), info = "fill_higher_ranks() argument was renamed fill_ranks")
})

test_that("input_rank is never read from the stamped taxon_name_rank column", {
  # The priors' taxon_name_rank is stamped "species" on every row so that
  # join_priors() has a non-NA key; it is not an observation of rank. Fed to
  # input_rank it would assert species for a genus-rank name, which selects a
  # homonym node without consulting decisions and weakens the lineage gate.
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")

  calls <- .template_calls(f, "TaxaTools", c("verify_taxon_names", "fill_higher_ranks"))
  reads_stamp <- vapply(calls, function(cl) {
    arg <- as.list(cl)[["input_rank"]]
    !is.null(arg) && "taxon_name_rank" %in% all.names(arg)
  }, logical(1))
  expect_false(any(reads_stamp),
               info = paste(sum(reads_stamp), "lookup call(s) take input_rank from taxon_name_rank"))
})

test_that("every posterior_consensus() call in the template names its consensus_method", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")

  calls <- .template_calls(f, "TaxaAssign", "posterior_consensus")
  expect_gt(length(calls), 0L)
  has <- vapply(calls, function(cl) "consensus_method" %in% names(as.list(cl)), logical(1))
  expect_true(all(has),
              info = paste(sum(!has), "posterior_consensus() call(s) rely on the default method"))
})

test_that("every review_assignments() call in the template passes the fit columns", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")

  calls <- .template_calls(f, "TaxaFlag", "review_assignments")
  expect_gt(length(calls), 0L)
  has <- vapply(calls, function(cl) {
    all(c("poor_absolute_fit_col", "best_identity_col") %in% names(as.list(cl)))
  }, logical(1))
  expect_true(all(has))
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

# --- GBIF key handling -------------------------------------------------------
# Both failures guarded here shipped in the generated template: the occurrence
# step passed get_keys_from_context()'s RESULT TABLE where an integer vector
# was required (as.integer() on a data frame is an error, so the step could not
# run), and nothing ever inspected matchType, so an unresolved or fuzzily
# matched taxon reached the fetch -- where an NA key is dropped silently and a
# FUZZY or HIGHERRANK key returns another taxon's records.

test_that("the template passes a usageKey vector to fetch_gbif_occurrences, not the key table", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  skip_if_not(grepl("get_keys_from_context", txt, fixed = TRUE),
              "this template does not fetch GBIF occurrences")

  # The variable get_keys_from_context() is assigned to.
  m <- regmatches(txt, regexpr(
    "[A-Za-z_.][A-Za-z_.0-9]*[ \t]*<-[ \t]*TaxaFetch::get_keys_from_context", txt))
  expect_length(m, 1L)
  v <- sub("[ \t]*<-.*", "", m)
  expect_true(nzchar(v))

  # It must be subset by usageKey before use ...
  expect_true(grepl(paste0(v, "$usageKey"), txt, fixed = TRUE))
  # ... and the table itself must never be handed to the fetch, which would
  # raise "'list' object cannot be coerced to type 'integer'".
  expect_false(grepl(paste0("keys[ \t]*=[ \t]*", v, "[ \t]*(,|\\))"), txt))
})

test_that("the template refuses a GBIF key that did not resolve exactly, before fetching", {
  f <- .tmpl_path()
  skip_if(is.null(f), "repo root or template not found")
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  skip_if_not(grepl("get_keys_from_context", txt, fixed = TRUE),
              "this template does not fetch GBIF occurrences")

  expect_true(grepl("matchType", txt, fixed = TRUE))
  # Every matchType that must not pass unexamined is named.
  for (mt in c("NONE", "FUZZY", "HIGHERRANK", "LOOKUP_RECOVERED")) {
    expect_true(grepl(mt, txt, fixed = TRUE), info = mt)
  }
  # An unresolved key is caught too, not left to be dropped silently.
  expect_true(grepl("is.na(key_matches$usageKey)", txt, fixed = TRUE))

  # The check must come BEFORE the request, or it guards nothing.
  #
  # Compare the guard against the CALL, and match the call by its NAMESPACED
  # form. The snippet explains in comments why fetch_gbif_occurrences() takes
  # the usageKey column and that it drops NA keys silently, so the bare name --
  # with or without "(" -- occurs in prose ABOVE the guard, and regexpr() on it
  # finds a comment rather than the call. Only the call is written
  # "TaxaFetch::fetch_gbif_occurrences(". An earlier form of this assertion
  # compared bare strings and so compared one comment against another.
  guard_at <- regexpr("did not resolve to a trustworthy GBIF key", txt, fixed = TRUE)[[1L]]
  call_at <- regexpr("TaxaFetch::fetch_gbif_occurrences(", txt, fixed = TRUE)[[1L]]
  expect_gt(guard_at, 0L)
  expect_gt(call_at, 0L)
  expect_lt(guard_at, call_at)
})
