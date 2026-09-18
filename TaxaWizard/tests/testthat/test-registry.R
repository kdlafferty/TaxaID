# Tests for R/registry.R -- the introspected function registry that
# replaced the old per-package metadata JSON files on 2026-09-18 (see
# ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md, section P1).
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

test_that(".compress_registry() contains no line for a name that is not an export", {
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  skip_if(length(installed) == 0L, "no TaxaID packages installed")

  reg <- workflow_registry(packages = installed)
  compressed <- TaxaWizard:::.compress_registry(reg)

  lines <- strsplit(compressed, "\n", fixed = TRUE)[[1]]
  fn_lines <- lines[grepl("^- ", lines)]

  offenders <- character(0)
  for (line in fn_lines) {
    # "- Pkg::fn(...) | title"
    m <- regmatches(line, regexec("^- ([A-Za-z][A-Za-z0-9._]*)::(\\S+?)\\(", line))[[1]]
    if (length(m) < 3L) {
      offenders <- c(offenders, paste("unparseable line:", line))
      next
    }
    pkg <- m[2]
    fn <- m[3]
    if (!pkg %in% installed) next
    exports <- getNamespaceExports(pkg)
    if (!fn %in% exports) {
      offenders <- c(offenders, sprintf("%s::%s is not an export of %s", pkg, fn, pkg))
    }
  }

  expect_true(
    length(offenders) == 0L,
    info = paste(c("Compressed registry lines for non-exports:", offenders), collapse = "\n")
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
