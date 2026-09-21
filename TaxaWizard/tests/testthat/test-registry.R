# Tests for R/registry.R -- the introspected function registry that
# replaced the old per-package metadata JSON files on 2026-09-18 (see
# TaxaID_dev/ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md (sibling development repository), section P1).
#
# These are offline: no network calls, no LLM calls. Every check reads the
# TaxaID packages actually installed in the current library (getNamespace
# Exports()/formals()/tools::Rd_db()), which is also what workflow_registry()
# itself does -- there is no separate "expected" fixture to drift out of
# sync, by design (DERIVE, DON'T DECLARE).

test_that("workflow_registry() returns a non-empty entry for every installed package", {
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  skip_if(length(installed) == 0L, "no TaxaID packages installed")

  reg <- workflow_registry(packages = installed, refresh = TRUE)

  expect_setequal(names(reg), installed)
  for (p in installed) {
    entry <- reg[[p]]
    expect_true(is.list(entry))
    expect_equal(entry$package, p)
    expect_true(nzchar(entry$version))
    expect_true(length(entry$functions) > 0L, info = p)

    # Every function entry has the documented shape.
    fn <- entry$functions[[1L]]
    expect_true(all(c("name", "title", "description", "params", "value") %in% names(fn)))
  }
})

test_that("workflow_registry() functions are alphabetical within each package", {
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  skip_if(length(installed) == 0L, "no TaxaID packages installed")

  reg <- workflow_registry(packages = installed)
  for (p in installed) {
    fn_names <- vapply(reg[[p]]$functions, `[[`, "", "name")
    expect_identical(fn_names, sort(fn_names), info = p)
  }
})

test_that("every function named in a snippet or an edge's functions[] has a registry entry", {
  # The structural-guard equivalent of test-graph.R's export-existence
  # checks, now run against the SAME live truth the registry itself reads
  # (getNamespaceExports()) rather than a hand-kept JSON file.
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  skip_if(length(installed) == 0L, "no TaxaID packages installed")

  reg <- workflow_registry(packages = installed)
  registered <- unlist(lapply(reg, function(pkg) {
    vapply(pkg$functions, `[[`, "", "name")
  }))

  graph_path <- system.file("graph", "workflow_graph.json", package = "TaxaWizard")
  skip_if(!nzchar(graph_path), "workflow_graph.json not found (package not installed)")
  graph <- jsonlite::fromJSON(graph_path, simplifyVector = FALSE)

  offenders <- character(0)

  # (b1) every edge's functions[] entry
  for (edge in graph$edges) {
    edge_pkgs <- unlist(edge$packages)
    if (!all(vapply(edge_pkgs, function(p) p %in% installed, logical(1)))) next
    for (fn in unlist(edge$functions)) {
      if (!fn %in% registered) {
        offenders <- c(offenders, sprintf("edge '%s': %s has no registry entry", edge$id, fn))
      }
    }
  }

  # (b2) every Pkg::fn( call in a snippet file
  snippet_dir <- system.file("graph", "snippets", package = "TaxaWizard")
  if (nzchar(snippet_dir)) {
    files <- list.files(snippet_dir, pattern = "\\.R$", full.names = TRUE)
    call_re <- "[A-Za-z][A-Za-z0-9._]*::[A-Za-z.][A-Za-z0-9._]*\\("
    for (f in files) {
      code_only <- paste(sub("#.*$", "", readLines(f, warn = FALSE)), collapse = "\n")
      calls <- regmatches(code_only, gregexpr(call_re, code_only, perl = TRUE))[[1]]
      if (length(calls) == 0L) next
      calls <- unique(sub("\\($", "", calls))
      for (call in calls) {
        pkg <- sub("::.*$", "", call)
        fn <- sub("^.*::", "", call)
        if (!pkg %in% installed) next
        if (!fn %in% registered) {
          offenders <- c(offenders, sprintf(
            "%s: %s::%s has no registry entry", basename(f), pkg, fn
          ))
        }
      }
    }
  }

  expect_true(
    length(offenders) == 0L,
    info = paste(c("Functions referenced but missing from the registry:", offenders), collapse = "\n")
  )
})

test_that("workflow_registry() never carries an entry for a name that is not an export", {
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  skip_if(length(installed) == 0L, "no TaxaID packages installed")

  reg <- workflow_registry(packages = installed)

  offenders <- character(0)
  for (pkg_name in names(reg)) {
    exports <- getNamespaceExports(pkg_name)
    for (fn in reg[[pkg_name]]$functions) {
      if (!fn$name %in% exports) {
        offenders <- c(offenders, sprintf("%s::%s is not an export of %s", pkg_name, fn$name, pkg_name))
      }
    }
  }

  expect_true(
    length(offenders) == 0L,
    info = paste(c("Registry entries for non-exports:", offenders), collapse = "\n")
  )
})

test_that("workflow_registry() cache round-trips and evicts stale files", {
  skip_if_not_installed("TaxaFlag")

  cache_dir <- file.path(tools::R_user_dir("TaxaWizard", "cache"), "registry")

  reg1 <- workflow_registry(packages = "TaxaFlag", refresh = TRUE)
  files_after_first <- list.files(cache_dir, pattern = "^TaxaFlag_.*\\.rds$", full.names = TRUE)
  expect_equal(length(files_after_first), 1L)

  # Plant a deliberately stale cache file for the same package under a
  # different fake version/build key, then confirm the next refresh=TRUE
  # write deletes it (only the current file for this package should survive).
  stale_file <- file.path(cache_dir, "TaxaFlag_0.0.9_00000000000000.rds")
  saveRDS(list(package = "TaxaFlag", version = "0.0.9"), stale_file)
  expect_true(file.exists(stale_file))

  reg2 <- workflow_registry(packages = "TaxaFlag", refresh = TRUE)
  files_after_second <- list.files(cache_dir, pattern = "^TaxaFlag_.*\\.rds$", full.names = TRUE)
  expect_equal(length(files_after_second), 1L)
  expect_false(file.exists(stale_file))

  # And a plain (refresh = FALSE) call reads back the same cached content.
  reg3 <- workflow_registry(packages = "TaxaFlag", refresh = FALSE)
  expect_identical(reg2[["TaxaFlag"]], reg3[["TaxaFlag"]])
})

test_that("workflow_registry() skips an uninstalled package with a message, not an error", {
  expect_message(
    reg <- workflow_registry(packages = "NotARealTaxaIDPackage"),
    "not installed"
  )
  expect_equal(length(reg), 0L)
})

test_that(".registry_docs() reports required/default status correctly", {
  skip_if_not_installed("TaxaAssign")
  reg <- workflow_registry(packages = "TaxaAssign")
  docs <- TaxaWizard:::.registry_docs(reg, "score_consensus", packages = "TaxaAssign")
  expect_true(grepl("- match_df: .*\\(REQUIRED\\)", docs))
  expect_true(grepl("\\[default: 0\\]", docs, fixed = FALSE))
})

test_that(".registry_docs() reports a function absent from the registry gracefully", {
  reg <- list(TaxaAssign = list(package = "TaxaAssign", functions = list()))
  docs <- TaxaWizard:::.registry_docs(reg, "not_a_real_function")
  expect_true(grepl("no registry entry available", docs, fixed = TRUE))
})

test_that("phase_parameterize.md's teaching example uses only real registry names", {
  # 2026-09-18: the prompt's function-specific parameter enumeration was
  # stripped (the registry is now the sole authority), but one illustrative
  # WRONG/RIGHT code example was deliberately kept to teach the "reference
  # parameter variables, don't hardcode" rule. This guards that the example
  # didn't drift from the real, registry-derivable signatures.
  skip_if_not_installed("TaxaAssign")
  path <- system.file("prompts", "phase_parameterize.md", package = "TaxaWizard")
  skip_if(!nzchar(path), "prompt not installed")
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")

  reg <- workflow_registry(packages = "TaxaAssign")
  fn_by_name <- stats::setNames(reg$TaxaAssign$functions,
    vapply(reg$TaxaAssign$functions, `[[`, "", "name")
  )

  expect_true(grepl("score_consensus(match_df,", txt, fixed = TRUE))
  expect_true(grepl("build_context(taxon_names", txt, fixed = TRUE))
  expect_true(all(c("score_consensus", "build_context") %in% names(fn_by_name)))

  sc_params <- vapply(fn_by_name$score_consensus$params, `[[`, "", "name")
  bc_params <- vapply(fn_by_name$build_context$params, `[[`, "", "name")
  expect_true(all(c("min_score", "max_gap", "rank_thresholds") %in% sc_params))
  expect_true(all(c("geographic_hint", "llm_fn") %in% bc_params))
})

testthat::test_that("every registry function has a title and description (Rd parsing invariant)", {
  for (p in TAXAID_PACKAGES) testthat::skip_if_not_installed(p)
  reg <- workflow_registry()
  missing_docs <- character()
  for (pkg in reg) {
    for (fn in pkg$functions) {
      if (!nzchar(fn$title %||% "") || !nzchar(fn$description %||% "")) {
        missing_docs <- c(missing_docs, paste0(pkg$package, "::", fn$name))
      }
    }
  }
  # 0 of 204 exports lacked docs on 2026-09-18; a regression here means the
  # Rd parser broke (e.g. the blank-line-after-header truncation bug), not
  # that a package lost its documentation.
  testthat::expect_length(missing_docs, 0)
})


# --- P1b: structural \arguments parsing ---------------------------------------
# The parser these cover replaced one that rendered \arguments with Rd2txt()
# and re-parsed the text. Rd2txt RIGHT-ALIGNS argument terms into a column, so
# any term shorter than the widest was emitted with leading whitespace and read
# as a continuation of the item above it: its doc was lost and glued onto its
# neighbour. Measured at the time: 318 of 1387 parameters had no doc, and 233
# survivors carried a lost neighbour's text.

# Parse a literal .Rd source string into the tree tools::Rd_db() would yield.
.test_rd <- function(txt) {
  f <- tempfile(fileext = ".Rd")
  on.exit(unlink(f), add = TRUE)
  writeLines(txt, f)
  tools::parse_Rd(f)
}

.test_args_node <- function(rd) {
  tags <- vapply(rd, function(x) attr(x, "Rd_tag") %||% "", character(1))
  rd[[which(tags == "\\arguments")[1L]]]
}

test_that(".rd_arguments() finds every term regardless of its width", {
  # `q` and `mid` are narrower than `a_very_wide_parameter`, which is exactly
  # the shape that made Rd2txt right-align them into a leading-whitespace
  # column. All four must come back, each with its OWN text.
  rd <- .test_rd(c(
    "\\name{widths}", "\\title{Widths}",
    "\\arguments{",
    "  \\item{a_very_wide_parameter}{The widest term, flush left.}",
    "  \\item{q}{A one-letter term.}",
    "  \\item{mid}{A middling term.}",
    "  \\item{another_extremely_wide_one}{The widest of all.}",
    "}"
  ))
  args <- TaxaWizard:::.rd_arguments(.test_args_node(rd))

  expect_setequal(
    names(args),
    c("a_very_wide_parameter", "q", "mid", "another_extremely_wide_one")
  )
  expect_equal(args[["q"]], "A one-letter term.")
  expect_equal(args[["mid"]], "A middling term.")
  # The narrow terms' text must NOT have been absorbed by the wide one.
  expect_false(grepl("one-letter", args[["a_very_wide_parameter"]], fixed = TRUE))
})

test_that(".rd_arguments() keeps a multi-paragraph description as ONE parameter", {
  # A continuation paragraph containing a colon is what made the old
  # text-based parser invent a bogus parameter.
  rd <- .test_rd(c(
    "\\name{multi}", "\\title{Multi}",
    "\\arguments{",
    "  \\item{bracket_fallback}{First paragraph of the description.",
    "",
    "    Second paragraph. Note: this colon used to start a bogus parameter.}",
    "  \\item{after}{Follows the multi-paragraph item.}",
    "}"
  ))
  args <- TaxaWizard:::.rd_arguments(.test_args_node(rd))

  expect_setequal(names(args), c("bracket_fallback", "after"))
  expect_match(args[["bracket_fallback"]], "First paragraph")
  expect_match(args[["bracket_fallback"]], "Second paragraph")
  expect_equal(args[["after"]], "Follows the multi-paragraph item.")
})

test_that(".rd_arguments() documents every name sharing one \\item", {
  rd <- .test_rd(c(
    "\\name{shared}", "\\title{Shared}",
    "\\arguments{",
    "  \\item{lat_col, lon_col}{Coordinate column names.}",
    "}"
  ))
  args <- TaxaWizard:::.rd_arguments(.test_args_node(rd))

  expect_setequal(names(args), c("lat_col", "lon_col"))
  expect_equal(args[["lat_col"]], args[["lon_col"]])
})

test_that(".rd_text() renders markup as text and drops non-visible nodes", {
  rd <- .test_rd(c(
    "\\name{markup}", "\\title{Markup}",
    "\\arguments{",
    "  \\item{styled}{Use \\code{NULL} or \\emph{other}, see \\link{elsewhere}.}",
    "  \\item{mathy}{Weight \\eqn{\\lambda}{lambda} applies.}",
    "  \\item{branchy}{Kept \\if{latex}{in latex} always.}",
    "}"
  ))
  args <- TaxaWizard:::.rd_arguments(.test_args_node(rd))

  expect_equal(args[["styled"]], "Use NULL or other, see elsewhere.")
  # \eqn{latex}{ascii}: the ASCII branch, never the LaTeX source.
  expect_equal(args[["mathy"]], "Weight lambda applies.")
  expect_false(grepl("\\lambda", args[["mathy"]], fixed = TRUE))
  # \if{format}{text}: the text, never the bare format name.
  expect_equal(args[["branchy"]], "Kept in latex always.")
  expect_false(grepl("latex}", args[["branchy"]], fixed = TRUE))
})

test_that("every documented parameter of every installed export carries a doc", {
  # The live guard. Scoped to the PARSER, not to the sibling packages' doc
  # hygiene: a formal only has to have a doc when the Rd actually documents a
  # term of that name. Offenders are named, because a count alone would not
  # say which function to go and look at.
  reg <- workflow_registry()
  skip_if(length(reg) == 0L, "no TaxaID packages installed")

  offenders <- character()
  for (pkg in names(reg)) {
    rd_db <- tryCatch(tools::Rd_db(pkg), error = function(e) NULL)
    if (is.null(rd_db)) next
    alias_map <- TaxaWizard:::.rd_alias_map(rd_db)

    for (fn in reg[[pkg]]$functions) {
      rd_entry <- alias_map[[fn$name]]
      if (is.null(rd_entry)) next
      tags <- vapply(rd_entry, function(x) attr(x, "Rd_tag") %||% "", character(1))
      if (!any(tags == "\\arguments")) next

      documented <- names(TaxaWizard:::.rd_arguments(rd_entry[[which(tags == "\\arguments")[1L]]]))
      for (p in fn$params) {
        if (p$name %in% documented && (is.null(p$doc) || !nzchar(p$doc))) {
          offenders <- c(offenders, paste0(pkg, "::", fn$name, "(", p$name, ")"))
        }
      }
    }
  }

  expect_equal(
    offenders, character(),
    info = paste("documented parameters with no doc in the registry:",
                 paste(offenders, collapse = ", "))
  )
})

test_that("the registry cache key carries the schema version", {
  # Package version and Built date do not move when TaxaWizard's own parsing
  # changes, so without this a parser fix never reaches a warm cache.
  skip_if_not_installed("TaxaFlag")
  cache_dir <- file.path(tools::R_user_dir("TaxaWizard", "cache"), "registry")

  workflow_registry(packages = "TaxaFlag", refresh = TRUE)
  files <- list.files(cache_dir, pattern = "^TaxaFlag_.*\\.rds$")

  expect_equal(length(files), 1L)
  expect_match(files[1L], sprintf("_v%d\\.rds$", TaxaWizard:::REGISTRY_SCHEMA))
})

test_that("registry text does not depend on the global useFancyQuotes option", {
  # The pack has a byte-for-byte equality test, and Rd2txt renders \code{} via
  # R's quoting, which honours this option. Before it was pinned, whether that
  # test passed depended on an ambient setting rather than on the packages.
  skip_if_not_installed("TaxaTools")

  old <- options(useFancyQuotes = TRUE)
  on.exit(options(old), add = TRUE)
  a <- TaxaWizard:::.build_package_registry("TaxaTools", "0.1.0", "test")

  options(useFancyQuotes = FALSE)
  b <- TaxaWizard:::.build_package_registry("TaxaTools", "0.1.0", "test")

  expect_identical(a, b)
  # And the surviving form is ASCII, which is what the committed pack holds.
  descs <- paste(vapply(a$functions, function(f) f$description %||% "", ""), collapse = " ")
  expect_false(grepl("‘|’", descs))
})
