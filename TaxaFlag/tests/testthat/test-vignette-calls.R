# Structural guard: every `Pkg::fn()` call inside this package's vignettes/
# must name a real, currently-exported function of Pkg, called with only
# argument names that are real formals of that function. Vignette chunks in
# this package are almost entirely `eval = FALSE` (they call live GBIF/NCBI/
# LLM services), so nothing else checks them against the current API -- a
# renamed argument or removed export can rot silently in user-facing docs.
# This mirrors TaxaWizard's inst/graph/snippets guard
# (TaxaWizard/tests/testthat/test-graph.R) applied to .Rmd vignette chunks.
#
# Deliberately not knitr::purl(): a past bug in this repo involved purl()
# silently ignoring an option and dropping chunks. A plain fenced-block scan
# is more predictable. Comments are handled for free -- we parse() the
# extracted code and walk the resulting expression tree, and R's parser
# already drops comments, so a function merely named in a prose-style
# comment is never mistaken for a call.

.extract_rmd_chunks <- function(path) {
  lines <- readLines(path, warn = FALSE)
  chunks <- list()
  in_chunk <- FALSE
  start <- NA_integer_
  label <- NA_character_
  for (i in seq_along(lines)) {
    if (!in_chunk && grepl("^```\\{r", lines[i])) {
      in_chunk <- TRUE
      start <- i + 1L
      label <- lines[i]
    } else if (in_chunk && grepl("^```\\s*$", lines[i])) {
      in_chunk <- FALSE
      body <- if (start <= i - 1L) lines[start:(i - 1L)] else character(0)
      chunks[[length(chunks) + 1]] <- list(label = label, body = body)
    }
  }
  chunks
}

# Recursively collect `pkg::fn(...)` call nodes from a parsed expression.
# A chunk may not parse standalone if it only makes sense in the context of
# an earlier chunk's objects -- that's fine, this is purely a syntax walk,
# nothing here is ever evaluated.
.find_pkgfn_calls <- function(expr, pkgs, out = list()) {
  if (is.call(expr)) {
    fn_part <- expr[[1]]
    if (is.call(fn_part) && identical(fn_part[[1]], as.name("::"))) {
      pkg <- as.character(fn_part[[2]])
      fname <- as.character(fn_part[[3]])
      if (pkg %in% pkgs) {
        out[[length(out) + 1]] <- list(pkg = pkg, fn = fname, call = expr)
      }
    }
    n <- length(expr)
    if (n >= 1) {
      for (i in seq_len(n)) {
        # NB: a call element can be the "missing argument" sentinel (e.g.
        # from `x[1, ]`). Never bind it to a bare variable before testing
        # it -- doing so raises "argument is missing" even outside a call.
        if (!identical(expr[[i]], quote(expr = ))) {
          out <- .find_pkgfn_calls(expr[[i]], pkgs, out)
        }
      }
    }
  }
  out
}

test_that("every Pkg::fn() call in this package's vignettes is a real, current export called with valid argument names", {
  vign_dir <- testthat::test_path("..", "..", "vignettes")
  if (!dir.exists(vign_dir)) {
    testthat::skip("vignettes/ directory not found next to this package (source layout unavailable here)")
  }

  rmd_files <- list.files(vign_dir, pattern = "\\.Rmd$", full.names = TRUE)
  testthat::skip_if(length(rmd_files) == 0L, "no .Rmd files found in vignettes/")

  taxaid_pkgs <- c(
    "TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch", "TaxaLikely",
    "TaxaExpect", "TaxaAssign", "TaxaFlag", "TaxaWizard"
  )
  for (pkg in taxaid_pkgs) testthat::skip_if_not_installed(pkg)

  offenders <- character(0)

  for (rmd in rmd_files) {
    chunks <- .extract_rmd_chunks(rmd)
    for (ch in chunks) {
      code_text <- paste(ch$body, collapse = "\n")
      if (!nzchar(trimws(code_text))) next

      parsed <- tryCatch(parse(text = code_text, keep.source = FALSE), error = function(e) e)
      if (inherits(parsed, "error")) {
        offenders <- c(offenders, sprintf(
          "%s chunk '%s': chunk did not parse -- %s",
          basename(rmd), trimws(ch$label), conditionMessage(parsed)
        ))
        next
      }

      calls <- list()
      for (top in as.list(parsed)) calls <- .find_pkgfn_calls(top, taxaid_pkgs, calls)

      for (call_info in calls) {
        pkg <- call_info$pkg
        fn <- call_info$fn
        exports <- getNamespaceExports(pkg)
        if (!fn %in% exports) {
          offenders <- c(offenders, sprintf(
            "%s chunk '%s': %s::%s is not an export of %s",
            basename(rmd), trimws(ch$label), pkg, fn, pkg
          ))
          next
        }

        f <- get(fn, envir = asNamespace(pkg))
        if (!is.function(f)) next

        matched <- tryCatch(
          match.call(definition = f, call = call_info$call),
          error = function(e) e
        )
        if (inherits(matched, "error")) {
          offenders <- c(offenders, sprintf(
            "%s chunk '%s': %s::%s(...) -- %s",
            basename(rmd), trimws(ch$label), pkg, fn, conditionMessage(matched)
          ))
        }
      }
    }
  }

  expect_true(length(offenders) == 0L,
    info = paste(c("Offending vignette calls:", offenders), collapse = "\n")
  )
})
