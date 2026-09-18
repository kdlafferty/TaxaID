# ==============================================================================
# validate.R
# TaxaWizard -- snippet validator (P2)
#
# .validate_snippets() AST-walks every `inst/graph/snippets/*.R` file and
# reports two classes of drift against the INSTALLED TaxaID packages:
#   - not_exported:    a `Pkg::fn()` call where `fn` is not (or no longer) an
#                       export of `Pkg` (Pkg is one of TAXAID_PACKAGES).
#   - stale_argument:  a named argument that is not among the installed
#                       function's real formals (ignored when the function's
#                       formals include `...`).
# A snippet that fails to parse once its `{{placeholder}}` tokens are
# replaced is reported as parse_error (not walked further). A bare call
# (no `Pkg::`) that resolves to neither base/utils/stats nor any TaxaID
# export is reported as unknown_bare_call at "warn" severity -- worth
# knowing about, but not a drift failure, since a snippet may legitimately
# call a function from some other Imports/Suggests package bare.
#
# This is a straight port of diagnostics/workflow_checks/check_stale_
# arguments.R's AST-walk logic (named args vs. formals) from a standalone
# Rscript run over production workflow files to an in-package function run
# over the snippet templates themselves, reading formals from the
# introspected registry (R/registry.R) instead of re-loading every package
# by hand. See ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md,
# section "P2 Snippet validator + Tier-B fallback".
# ==============================================================================


#' Validate Every Snippet Against the Installed Packages
#'
#' Walks the R AST of every code snippet referenced by the workflow graph's
#' edges (or a subset of them, via \code{edge_ids}) and reports drift between
#' what a snippet calls and what the installed TaxaID packages actually
#' export/accept.
#'
#' @param graph Optional graph object from \code{\link{.load_graph}}.
#' @param registry Optional registry from \code{\link{workflow_registry}}.
#' @param edge_ids Optional character vector restricting validation to these
#'   edge ids (default: every edge in \code{graph}). Also accepts edges that
#'   are not in the real installed graph, as long as they are present in
#'   \code{graph$edges} -- this is what makes the function testable with an
#'   injected graph without ever touching a real snippet file.
#'
#' @return A data.frame with columns \code{edge_id}, \code{function},
#'   \code{problem} (\code{"not_exported"}, \code{"stale_argument"},
#'   \code{"parse_error"}, or \code{"unknown_bare_call"}), and
#'   \code{detail}. Zero rows when nothing to report.
#' @noRd
.validate_snippets <- function(graph = NULL, registry = NULL, edge_ids = NULL) {
  if (is.null(graph)) graph <- .load_graph()
  if (is.null(registry)) registry <- workflow_registry()

  edges <- graph$edges %||% list()
  if (!is.null(edge_ids)) {
    edges <- Filter(function(e) e$id %in% edge_ids, edges)
  }

  fn_index <- .registry_fn_index(registry)
  taxaid_pkgs <- names(registry)

  rows <- list()
  seen <- new.env(parent = emptyenv())
  add_row <- function(edge_id, fn, problem, detail) {
    key <- paste(edge_id, fn, problem, detail, sep = "\r")
    if (exists(key, envir = seen, inherits = FALSE)) {
      return(invisible())
    }
    assign(key, TRUE, envir = seen)
    rows[[length(rows) + 1L]] <<- list(
      edge_id = edge_id, `function` = fn %||% NA_character_,
      problem = problem, detail = detail
    )
  }

  for (edge in edges) {
    .validate_one_snippet(edge, fn_index, taxaid_pkgs, add_row)
  }

  .validate_rows_to_df(rows)
}


#' Build a Function-Name -> (Package, Registry Entry) Index
#'
#' A function name can be exported by more than one TaxaID package (rare,
#' but not impossible) -- each name maps to a list of \code{list(pkg=, entry=)}
#' hits.
#'
#' @param registry Named list from \code{\link{workflow_registry}}.
#' @return Named list: function name -> list of \code{list(pkg, entry)}.
#' @noRd
.registry_fn_index <- function(registry) {
  idx <- list()
  for (pkg_name in names(registry)) {
    pkg <- registry[[pkg_name]]
    for (fn in pkg$functions %||% list()) {
      idx[[fn$name]] <- c(idx[[fn$name]], list(list(pkg = pkg_name, entry = fn)))
    }
  }
  idx
}


#' Validate One Edge's Snippet File
#' @noRd
.validate_one_snippet <- function(edge, fn_index, taxaid_pkgs, add_row) {
  snippet_name <- edge$snippet
  if (is.null(snippet_name) || !nzchar(snippet_name)) {
    return(invisible())
  }

  # An edge injected for testing may name an absolute path to a temp file
  # directly (so a test never has to touch a real inst/graph/snippets/ file);
  # a real edge names a bare filename resolved inside the installed package.
  snippet_file <- if (file.exists(snippet_name)) {
    snippet_name
  } else {
    system.file("graph", "snippets", snippet_name, package = "TaxaWizard")
  }
  if (!nzchar(snippet_file) || !file.exists(snippet_file)) {
    add_row(edge$id, NA_character_, "parse_error",
      sprintf("snippet file not found: %s", snippet_name))
    return(invisible())
  }

  raw <- paste(readLines(snippet_file, warn = FALSE), collapse = "\n")
  filled <- gsub("\\{\\{[A-Za-z0-9_]+\\}\\}", ".dummy_value", raw)

  exprs <- tryCatch(parse(text = filled), error = function(e) e)
  if (inherits(exprs, "error") || inherits(exprs, "condition")) {
    add_row(edge$id, NA_character_, "parse_error", conditionMessage(exprs))
    return(invisible())
  }

  # A snippet may define its own local helper (e.g. a closure assigned to
  # `.foo <- function(...) ...` and called later in the same snippet) --
  # those are neither a TaxaID export nor a base/utils/stats function, so
  # they must be excluded from the bare-call resolution below or every one
  # would misreport as unknown_bare_call.
  local_fns <- .collect_local_functions(exprs)

  walk <- function(e) {
    if (is.call(e)) {
      .validate_one_call(e, edge$id, fn_index, taxaid_pkgs, local_fns, add_row)
    }
    if (is.recursive(e)) {
      for (i in seq_along(e)) {
        if (!is.null(e[[i]])) tryCatch(walk(e[[i]]), error = function(err) NULL)
      }
    }
  }
  for (ex in exprs) walk(ex)

  invisible()
}


#' Collect Names Locally Assigned a `function(...)` Value in a Snippet
#'
#' @param exprs A parsed expression vector (from \code{parse()}).
#' @return Character vector of locally-defined function names.
#' @noRd
.collect_local_functions <- function(exprs) {
  names_found <- character(0)
  walk <- function(e) {
    if (is.call(e) && length(e) == 3L && is.symbol(e[[1L]]) &&
      as.character(e[[1L]]) %in% c("<-", "=", "<<-") && is.symbol(e[[2L]])) {
      rhs <- e[[3L]]
      if (is.call(rhs) && is.symbol(rhs[[1L]]) &&
        identical(as.character(rhs[[1L]]), "function")) {
        names_found <<- c(names_found, as.character(e[[2L]]))
      }
    }
    if (is.recursive(e)) {
      for (i in seq_along(e)) {
        if (!is.null(e[[i]])) tryCatch(walk(e[[i]]), error = function(err) NULL)
      }
    }
  }
  for (ex in exprs) walk(ex)
  unique(names_found)
}


#' Resolve a Call's Head to a (Package-Qualified or Bare) Name
#' @return \code{list(pkg = <character or NULL>, name = <character>)}, or
#'   \code{NULL} if the call's head is not a plain symbol or \code{Pkg::fn}
#'   form (e.g. an anonymous function expression).
#' @noRd
.resolve_call_head <- function(fn_sym) {
  if (is.symbol(fn_sym)) {
    return(list(pkg = NULL, name = as.character(fn_sym)))
  }
  if (is.call(fn_sym) && length(fn_sym) == 3L &&
    is.symbol(fn_sym[[1L]]) && as.character(fn_sym[[1L]]) %in% c("::", ":::")) {
    return(list(pkg = as.character(fn_sym[[2L]]), name = as.character(fn_sym[[3L]])))
  }
  NULL
}


#' Does This Bare Name Resolve to a Base/Utils/Stats Function?
#' @noRd
.bare_exists_in_base <- function(nm) {
  for (ns in c("package:base", "package:utils", "package:stats")) {
    found <- tryCatch(
      exists(nm, where = as.environment(ns), mode = "function", inherits = FALSE),
      error = function(e) FALSE
    )
    if (found) return(TRUE)
  }
  FALSE
}


#' Validate a Single Call Node
#' @noRd
.validate_one_call <- function(e, edge_id, fn_index, taxaid_pkgs, local_fns, add_row) {
  resolved <- .resolve_call_head(e[[1L]])
  if (is.null(resolved) || !nzchar(resolved$name)) {
    return(invisible())
  }
  nm <- resolved$name
  pkg_hint <- resolved$pkg

  if (is.null(pkg_hint) && nm %in% local_fns) {
    return(invisible()) # snippet's own locally-defined helper -- not a problem
  }

  arg_names <- names(e)
  arg_names <- arg_names[!is.na(arg_names) & nzchar(arg_names)]

  if (!is.null(pkg_hint)) {
    if (!pkg_hint %in% taxaid_pkgs) {
      return(invisible()) # not a TaxaID call -- out of scope
    }
    hits <- fn_index[[nm]]
    hit <- Find(function(m) identical(m$pkg, pkg_hint), hits)
    if (is.null(hit)) {
      add_row(
        edge_id, sprintf("%s::%s", pkg_hint, nm), "not_exported",
        sprintf("%s::%s is not exported by %s (installed)", pkg_hint, nm, pkg_hint)
      )
      return(invisible())
    }
    .validate_stale_argument(edge_id, sprintf("%s::%s", pkg_hint, nm), hit$entry, arg_names, add_row)
    return(invisible())
  }

  # Bare call.
  hits <- fn_index[[nm]]
  if (!is.null(hits)) {
    .validate_stale_argument(edge_id, nm, hits[[1L]]$entry, arg_names, add_row)
    return(invisible())
  }
  if (.bare_exists_in_base(nm)) {
    return(invisible())
  }
  add_row(
    edge_id, nm, "unknown_bare_call",
    sprintf(
      "bare call to `%s` resolved to neither base/utils/stats nor a TaxaID export",
      nm
    )
  )
  invisible()
}


#' Check a Resolved Function's Named Arguments Against Its Registry Formals
#' @noRd
.validate_stale_argument <- function(edge_id, label, fn_entry, arg_names, add_row) {
  if (length(arg_names) == 0L) {
    return(invisible())
  }
  param_names <- vapply(fn_entry$params %||% list(), function(p) p$name, character(1))
  if ("..." %in% param_names) {
    return(invisible()) # ... absorbs anything -- nothing can be "stale"
  }
  bad <- setdiff(arg_names, param_names)
  if (length(bad) == 0L) {
    return(invisible())
  }
  add_row(
    edge_id, label, "stale_argument",
    sprintf(
      "named argument(s) not in %s's installed formals: %s",
      label, paste(sort(bad), collapse = ", ")
    )
  )
  invisible()
}


#' Collapse the Row List Built by \code{add_row()} into a data.frame
#' @noRd
.validate_rows_to_df <- function(rows) {
  if (length(rows) == 0L) {
    return(data.frame(
      edge_id = character(), `function` = character(),
      problem = character(), detail = character(),
      stringsAsFactors = FALSE, check.names = FALSE
    ))
  }
  data.frame(
    edge_id  = vapply(rows, function(r) as.character(r$edge_id %||% NA), character(1)),
    `function` = vapply(rows, function(r) as.character(r$`function` %||% NA), character(1)),
    problem  = vapply(rows, function(r) as.character(r$problem %||% NA), character(1)),
    detail   = vapply(rows, function(r) as.character(r$detail %||% NA), character(1)),
    stringsAsFactors = FALSE, check.names = FALSE
  )
}
