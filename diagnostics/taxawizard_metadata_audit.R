#!/usr/bin/env Rscript
# TaxaWizard metadata-vs-reality drift auditor.
#
# For every function named in inst/metadata/<Package>.json, compares the JSON's
# declared inputs (name, required, default) against the REAL installed function's
# formals(). Flags:
#   - MISSING_FN     : metadata references a function that no longer exists/exports
#   - PARAM_NOT_REAL : metadata lists a param name that isn't a real formal
#   - REQUIRED_MISMATCH : metadata says required=TRUE/FALSE but real formal disagrees
#     (real formal has no default -> required; real formal has a default -> optional)
#   - MISSING_REQUIRED_PARAM : real function has a required (no-default) formal
#     that ISN'T in the metadata's inputs list at all (silent-omission risk)
#   - DEFAULT_MISMATCH : both have a default, but the literal text differs
#     (best-effort string compare -- flags for human review, not authoritative)
#
# Usage: Rscript taxawizard_metadata_audit.R
#   (run from anywhere; paths are hardcoded to this machine's TaxaID checkout)

.libPaths(c(path.expand("~/Library/R/4.0/library"), .libPaths()))
suppressMessages({
  library(jsonlite)
})

taxaid_root <- "~/My Drive/Rscripts/projects/TaxaID"
taxaid_root <- path.expand(taxaid_root)
metadata_dir <- file.path(taxaid_root, "TaxaWizard", "inst", "metadata")

pkgs <- c("TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
          "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag")

for (p in pkgs) {
  suppressWarnings(suppressMessages(
    requireNamespace(p, quietly = TRUE)
  ))
}

deparse_default <- function(x) {
  if (identical(x, quote(expr = ))) return(NA_character_)  # no default -> required
  tryCatch(paste(deparse(x), collapse = " "), error = function(e) NA_character_)
}

audit_one_package <- function(pkg) {
  json_path <- file.path(metadata_dir, paste0(pkg, ".json"))
  if (!file.exists(json_path)) {
    cat(sprintf("== %s: no metadata file, skipping ==\n", pkg))
    return(invisible(NULL))
  }
  meta <- fromJSON(json_path, simplifyDataFrame = FALSE)
  ns_exports <- tryCatch(getNamespaceExports(pkg), error = function(e) character(0))

  findings <- list()

  for (fn_entry in meta$functions) {
    fn_name <- fn_entry$name

    # Only check functions this package itself exports (cross-package-attributed
    # entries, if any, aren't this package's problem to fix).
    real_fn <- tryCatch(get(fn_name, envir = asNamespace(pkg)), error = function(e) NULL)
    exported <- fn_name %in% ns_exports

    if (is.null(real_fn)) {
      findings[[length(findings) + 1]] <- list(
        fn = fn_name, issue = "MISSING_FN",
        detail = sprintf("'%s' not found in %s namespace at all (renamed/removed?)", fn_name, pkg)
      )
      next
    }
    if (!exported) {
      findings[[length(findings) + 1]] <- list(
        fn = fn_name, issue = "NOT_EXPORTED",
        detail = sprintf("'%s' exists in %s but is not exported (internal-only?)", fn_name, pkg)
      )
    }
    if (!is.function(real_fn)) next

    real_formals <- formals(real_fn)
    real_names <- names(real_formals)
    real_required <- vapply(real_formals, function(d) identical(d, quote(expr = )), logical(1))
    names(real_required) <- real_names

    meta_inputs <- fn_entry$inputs
    if (is.null(meta_inputs)) meta_inputs <- list()
    meta_names <- vapply(meta_inputs, function(i) i$name %||% NA_character_, character(1))

    # PARAM_NOT_REAL: metadata param name isn't a real formal (and no ... catch-all)
    has_dots <- "..." %in% real_names
    for (i in seq_along(meta_inputs)) {
      mn <- meta_inputs[[i]]$name
      if (is.null(mn) || is.na(mn)) next
      if (!(mn %in% real_names) && !has_dots) {
        findings[[length(findings) + 1]] <- list(
          fn = fn_name, issue = "PARAM_NOT_REAL",
          detail = sprintf("metadata param '%s' is not a real formal of %s::%s(). Real formals: %s",
                            mn, pkg, fn_name, paste(real_names, collapse = ", "))
        )
      } else if (mn %in% real_names) {
        meta_required <- isTRUE(meta_inputs[[i]]$required)
        real_req_i <- unname(real_required[mn])
        if (!is.na(real_req_i) && meta_required != real_req_i) {
          findings[[length(findings) + 1]] <- list(
            fn = fn_name, issue = "REQUIRED_MISMATCH",
            detail = sprintf("param '%s' on %s::%s(): metadata says required=%s, real signature says required=%s",
                              mn, pkg, fn_name, meta_required, real_req_i)
          )
        }
        if (!is.na(real_req_i) && !real_req_i) {
          real_default_str <- deparse_default(real_formals[[mn]])
          meta_default <- meta_inputs[[i]]$default
          if (!is.null(meta_default) && !is.na(real_default_str)) {
            meta_default_str <- if (is.character(meta_default)) meta_default else deparse_default(meta_default)
            # loose compare: strip quotes/whitespace
            norm <- function(s) gsub("['\"[:space:]]", "", as.character(s))
            if (!identical(norm(real_default_str), norm(meta_default_str))) {
              findings[[length(findings) + 1]] <- list(
                fn = fn_name, issue = "DEFAULT_MISMATCH",
                detail = sprintf("param '%s' on %s::%s(): metadata default='%s', real default='%s' (verify -- string compare is best-effort)",
                                  mn, pkg, fn_name, meta_default_str, real_default_str)
              )
            }
          }
        }
      }
    }

    # MISSING_REQUIRED_PARAM: a real required formal not mentioned in metadata at all
    for (rn in real_names) {
      if (rn == "...") next
      if (isTRUE(real_required[[rn]]) && !(rn %in% meta_names)) {
        findings[[length(findings) + 1]] <- list(
          fn = fn_name, issue = "MISSING_REQUIRED_PARAM",
          detail = sprintf("%s::%s()'s real required param '%s' is absent from metadata entirely (interview would never ask for it)",
                            pkg, fn_name, rn)
        )
      }
    }
  }

  cat(sprintf("\n== %s (%d functions in metadata) ==\n", pkg, length(meta$functions)))
  if (length(findings) == 0) {
    cat("  no drift found\n")
  } else {
    for (f in findings) {
      cat(sprintf("  [%s] %s :: %s\n", f$issue, f$fn, f$detail))
    }
  }
  invisible(findings)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

all_findings <- lapply(pkgs, audit_one_package)
names(all_findings) <- pkgs

n_total <- sum(vapply(all_findings, length, integer(1)))
cat(sprintf("\n=== TOTAL: %d potential drift findings across %d packages ===\n", n_total, length(pkgs)))
cat("Note: PARAM_NOT_REAL and MISSING_FN are high-confidence (structural).\n")
cat("REQUIRED_MISMATCH is high-confidence. DEFAULT_MISMATCH and MISSING_REQUIRED_PARAM\n")
cat("need a human/LLM read -- some 'missing required params' are deliberately templated\n")
cat("via {{placeholder}} in snippets rather than listed as a formal input, and some\n")
cat("default-string mismatches are just formatting (e.g. NULL vs 'NULL').\n")
