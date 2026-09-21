# ==============================================================================
# setup.R
# TaxaWizard -- Setup checker, edge requirements, and input sniffer
#
# workflow_check() answers "is my machine ready to run this workflow?" --
# base R + jsonlite + httr2 only, no network unless category == "network",
# never prints or logs a key VALUE (set/unset only). Machine-readable: the
# engine injects its output into prompts, and the generated script's
# Step 0 stops the run when any row is status == "missing".
#
# sniff_input() answers "what TaxaWizard input-graph node does this file
# look like?" from real TaxaMatch/TaxaLikely reader header signatures.
#
# Source of the requirements table: inst/setup/requirements.json (hand-kept;
# see its own "_comment" field for provenance). Source of the per-edge
# `requires` tokens: inst/graph/workflow_graph.json.
# ==============================================================================


# ==============================================================================
# Constants
# ==============================================================================



# ==============================================================================
# Requirements table (inst/setup/requirements.json)
# ==============================================================================

#' Namespace cache for the parsed requirements table
#' @noRd
.requirements_env <- new.env(parent = emptyenv())

#' Load and cache \code{inst/setup/requirements.json}
#' @return A list with \code{$keys}, \code{$packages}, \code{$binaries},
#'   \code{$network}, \code{$groups} (all as nested lists, i.e. parsed with
#'   \code{simplifyVector = FALSE} -- consistent with \code{.load_graph()}).
#' @noRd
.load_requirements <- function() {
  cached <- .requirements_env$requirements
  if (!is.null(cached)) {
    return(cached)
  }

  path <- system.file("setup", "requirements.json", package = "TaxaWizard")
  if (!nzchar(path)) {
    stop("requirements.json not found. Is TaxaWizard installed?", call. = FALSE)
  }
  req <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  .requirements_env$requirements <- req
  req
}


# ==============================================================================
# Small shared helpers
# ==============================================================================

#' Is at least one of these environment variables non-empty?
#' @noRd
.env_is_set <- function(vars) {
  any(vapply(vars, function(v) nzchar(Sys.getenv(v, unset = "")), logical(1)))
}

#' Is this variable set in ~/.Renviron (vs only the current session)?
#'
#' The README's documented footgun: a key set with \code{Sys.setenv()} or by
#' an IDE for the current session only silently stops working on restart.
#' @noRd
.in_renviron <- function(var) {
  path <- path.expand("~/.Renviron")
  if (!file.exists(path)) {
    return(FALSE)
  }
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character())
  any(grepl(sprintf("^\\s*%s\\s*=", var), lines))
}

#' Build one check row as a plain list (component/category/status/detail/fix)
#' @noRd
.check_row <- function(component, category, status, detail, fix = "") {
  list(component = component, category = category, status = status, detail = detail, fix = fix)
}

#' Combine a list of \code{.check_row()} lists into a data.frame
#' @noRd
.rows_to_df <- function(rows) {
  if (length(rows) == 0L) {
    return(data.frame(
      component = character(), category = character(), status = character(),
      detail = character(), fix = character(), stringsAsFactors = FALSE
    ))
  }
  data.frame(
    component = vapply(rows, function(r) as.character(r$component %||% ""), character(1)),
    category  = vapply(rows, function(r) as.character(r$category %||% ""), character(1)),
    status    = vapply(rows, function(r) as.character(r$status %||% ""), character(1)),
    detail    = vapply(rows, function(r) as.character(r$detail %||% ""), character(1)),
    fix       = vapply(rows, function(r) as.character(r$fix %||% ""), character(1)),
    stringsAsFactors = FALSE
  )
}

#' Truncate a string for fixed-width printing
#' @noRd
.tw_trunc <- function(x, width) {
  x <- as.character(x)
  ifelse(nchar(x) > width, paste0(substr(x, 1L, width - 1L), "..."), x)
}


# ==============================================================================
# "r" category
# ==============================================================================

#' @noRd
.check_r <- function() {
  ver_ok <- getRversion() >= "4.1.0"
  list(
    .check_row(
      "R version", "r",
      if (ver_ok) "ok" else "missing",
      sprintf("Running R %s (need >= 4.1.0)", getRversion()),
      if (ver_ok) "" else "Install R >= 4.1 from https://cran.r-project.org/"
    ),
    .check_row(
      "R session type", "r",
      if (interactive()) "ok" else "warn",
      if (interactive()) {
        "interactive session (RStudio/console) -- provider auto-detection runs normally"
      } else {
        paste0(
          "non-interactive (e.g. Rscript) -- see README Troubleshooting: a key set only for ",
          "this session, or a package loaded via :: rather than library(), can silently skip ",
          "provider auto-detection"
        )
      },
      if (interactive()) {
        ""
      } else {
        paste0(
          "If you see \"no LLM provider configured\" despite a key being set, pass a provider ",
          "explicitly: llm_fn <- function(prompt) TaxaTools::call_api(prompt, provider = \"anthropic\")"
        )
      }
    )
  )
}


# ==============================================================================
# "package" category
# ==============================================================================

#' One package-check row
#' @noRd
.pkg_row <- function(pkg, level = "missing", install_fix = NULL) {
  installed <- requireNamespace(pkg, quietly = TRUE)
  status <- if (installed) "ok" else level
  detail <- if (installed) {
    ver <- tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NA_character_)
    built <- tryCatch(utils::packageDescription(pkg)$Built, error = function(e) NULL)
    sprintf(
      "installed, v%s%s",
      ver %||% "?",
      if (!is.null(built) && !is.na(built)) sprintf(" (built %s)", built) else ""
    )
  } else {
    "not installed"
  }
  fix <- if (installed) "" else (install_fix %||% sprintf('install.packages("%s")', pkg))
  .check_row(pkg, "package", status, detail, fix)
}

#' @noRd
.check_packages <- function(requirements) {
  rows <- lapply(TAXAID_PACKAGES, function(p) {
    .pkg_row(
      p,
      level = "missing",
      install_fix = sprintf(
        'remotes::install_github("DOI-USGS/TaxaID", subdir = "%s")', p
      )
    )
  })
  for (entry in requirements$packages) {
    rows[[length(rows) + 1L]] <- .pkg_row(
      entry$package,
      level = entry$level %||% "missing",
      install_fix = entry$install
    )
  }
  rows
}


# ==============================================================================
# "cache" category
# ==============================================================================

#' @noRd
.check_cache <- function() {
  pkgs <- c(TAXAID_PACKAGES, "TaxaWizard")

  report <- NULL
  if (requireNamespace("TaxaTools", quietly = TRUE) &&
    "taxaid_cache_report" %in% getNamespaceExports("TaxaTools")) {
    report <- tryCatch(
      suppressMessages(TaxaTools::taxaid_cache_report()),
      error = function(e) NULL
    )
  }

  lapply(pkgs, function(p) {
    dir <- tools::R_user_dir(p, "cache")
    if (!dir.exists(dir)) {
      return(.check_row(p, "cache", "ok", sprintf("%s (not yet created)", dir)))
    }
    writable <- file.access(dir, mode = 2) == 0

    if (!is.null(report) && "cache" %in% names(report) && p %in% report$cache) {
      r <- report[report$cache == p, ][1L, ]
      size_detail <- sprintf("%.1f MB, %d file(s)", r$size_mb, r$n_files)
    } else {
      f <- list.files(dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
      size_mb <- sum(file.size(f), na.rm = TRUE) / 1024^2
      size_detail <- sprintf("%.1f MB, %d file(s)", size_mb, length(f))
    }

    status <- if (writable) "ok" else "warn"
    .check_row(
      p, "cache", status,
      sprintf("%s -- %s%s", dir, size_detail, if (!writable) " (NOT writable)" else ""),
      if (!writable) {
        sprintf("Fix permissions on %s, or delete it and let it be recreated.", dir)
      } else {
        ""
      }
    )
  })
}


# ==============================================================================
# requires-token resolution: "key", "network", "binary" (and ad hoc "package")
# ==============================================================================

#' Union of `requires` tokens for the selected edges (or all edges when
#' `edges` is NULL), plus implied network checks for the LLM/GBIF key groups.
#' @noRd
.selected_requires_tokens <- function(graph, edges) {
  all_ids <- vapply(graph$edges, function(e) e$id, character(1))

  if (is.null(edges)) {
    sel <- graph$edges
  } else {
    unknown <- setdiff(edges, all_ids)
    if (length(unknown) > 0L) {
      warning(
        "workflow_check: unknown edge id(s) ignored: ", paste(unknown, collapse = ", "),
        call. = FALSE
      )
    }
    sel <- Filter(function(e) e$id %in% edges, graph$edges)
  }

  tokens <- unique(unlist(lapply(sel, function(e) e$requires)))
  if (is.null(tokens)) tokens <- character(0)
  tokens <- as.character(tokens)

  # A key GROUP requirement implies a network check against that group's
  # service -- workflow_check() itself derives this rather than every edge
  # repeating both tokens.
  if ("key:llm" %in% tokens) tokens <- union(tokens, "net:llm")
  if ("key:gbif" %in% tokens) tokens <- union(tokens, "net:gbif")

  tokens
}

#' Resolve one "key:" token (individual key, or a group like key:llm/key:gbif)
#' @noRd
.resolve_key_token <- function(token, requirements) {
  entry <- Find(function(k) identical(k$id, token), requirements$keys)

  if (!is.null(entry)) {
    envs <- as.character(unlist(entry$env))
    level <- entry$level %||% "missing"
    set <- .env_is_set(envs)
    status <- if (set) "ok" else level
    env_label <- paste(envs, collapse = "/")

    if (set) {
      persisted <- any(vapply(envs, .in_renviron, logical(1)))
      detail <- sprintf(
        "%s: set (%s)", env_label,
        if (persisted) "found in ~/.Renviron" else "session only -- not found in ~/.Renviron"
      )
      fix <- if (persisted) {
        ""
      } else {
        sprintf(
          "Currently set for this session only, so it will not survive an R restart. Persist it: %s",
          "usethis::edit_r_environ(); add it there; restart R."
        )
      }
    } else {
      detail <- sprintf("%s: not set", env_label)
      fix <- entry$fix %||% ""
    }
    return(.check_row(token, "key", status, detail, fix))
  }

  # Group token, e.g. "key:llm" / "key:gbif"
  gname <- sub("^key:", "", token)
  group <- requirements$groups[[gname]]
  if (!is.null(group)) {
    members <- Filter(function(k) identical(k$group, gname), requirements$keys)
    member_env1 <- vapply(members, function(k) as.character(unlist(k$env))[1], character(1))
    set_flags <- vapply(members, function(k) .env_is_set(as.character(unlist(k$env))), logical(1))
    any_set <- any(set_flags)
    status <- if (any_set) "ok" else (group$level %||% "missing")
    detail <- if (any_set) {
      sprintf("satisfied by: %s", paste(member_env1[set_flags], collapse = ", "))
    } else {
      sprintf("none set (any ONE of: %s)", paste(member_env1, collapse = ", "))
    }
    fix <- if (any_set) {
      ""
    } else {
      sprintf(
        "Set any ONE of: %s. usethis::edit_r_environ(); add it; restart R.",
        paste(member_env1, collapse = ", ")
      )
    }
    return(.check_row(token, "key", status, detail, fix))
  }

  .check_row(token, "key", "skip", "unrecognized requirement token (not in requirements.json)")
}

#' Known reachability targets for `net:llm`, keyed by TaxaID.provider
#' @noRd
.llm_provider_urls <- list(
  anthropic = "https://api.anthropic.com",
  gemini    = "https://generativelanguage.googleapis.com",
  openai    = "https://api.openai.com",
  ollama    = "http://localhost:11434"
)

#' A cheap reachability probe: TRUE on ANY HTTP response, FALSE only on a
#' connection-level failure (DNS/timeout/refused). Never throws.
#' @noRd
.net_reachable <- function(url, timeout_s = 5) {
  if (!requireNamespace("httr2", quietly = TRUE)) {
    return(NA)
  }
  tryCatch(
    {
      req <- httr2::request(url)
      req <- httr2::req_timeout(req, timeout_s)
      req <- httr2::req_error(req, is_error = function(resp) FALSE)
      httr2::req_perform(req)
      TRUE
    },
    error = function(e) FALSE
  )
}

#' Resolve one "net:" token
#' @noRd
.resolve_net_token <- function(token, requirements, offline) {
  if (isTRUE(offline)) {
    return(.check_row(token, "network", "skip", "skipped (options(TaxaWizard.offline = TRUE))"))
  }

  entry <- Find(function(n) identical(n$id, token), requirements$network)
  url <- if (!is.null(entry)) entry$url else NULL

  if (identical(token, "net:llm")) {
    provider <- getOption("TaxaID.provider")
    url <- if (!is.null(provider)) .llm_provider_urls[[provider]] else NULL
    if (is.null(url)) {
      return(.check_row(
        token, "network", "skip",
        sprintf(
          "no reachability check available for provider '%s' (unset, azure_openai, or a custom endpoint)",
          provider %||% "<unset>"
        )
      ))
    }
  }

  if (is.null(url) || !nzchar(url)) {
    return(.check_row(token, "network", "skip", "no url configured for this check"))
  }

  ok <- .net_reachable(url)
  if (is.na(ok)) {
    return(.check_row(token, "network", "skip", "httr2 not available"))
  }
  status <- if (ok) "ok" else "warn"
  .check_row(
    token, "network", status,
    sprintf("%s -- %s", url, if (ok) "reachable" else "unreachable within 5s (may be transient)"),
    if (ok) "" else "Check your internet connection, firewall, or VPN."
  )
}

#' Resolve one "bin:" token
#' @noRd
.resolve_bin_token <- function(token, requirements) {
  entry <- Find(function(b) identical(b$id, token), requirements$binaries)
  if (is.null(entry)) {
    return(.check_row(token, "binary", "skip", "unrecognized requirement token (not in requirements.json)"))
  }
  found <- nzchar(Sys.which(entry$binary))
  level <- entry$level %||% "missing"
  status <- if (found) "ok" else level
  .check_row(
    token, "binary", status,
    if (found) sprintf("%s found on PATH", entry$binary) else sprintf("%s not found on PATH", entry$binary),
    if (found) "" else (entry$install %||% "")
  )
}

#' Resolve one "pkg:" token from requires (redundant with the unconditional
#' package category when the package is already listed there; harmless).
#' @noRd
.resolve_pkg_token <- function(token, requirements) {
  entry <- Find(function(p) identical(p$id, token), requirements$packages)
  if (is.null(entry)) {
    return(.check_row(token, "package", "skip", "unrecognized requirement token (not in requirements.json)"))
  }
  .pkg_row(entry$package, level = entry$level %||% "missing", install_fix = entry$install)
}


# ==============================================================================
# workflow_check()
# ==============================================================================

#' Check the Local TaxaID Setup
#'
#' Reports whether this machine is ready to run TaxaID workflows: R version,
#' the 8 TaxaID packages (plus Bioconductor/optional extras), each package's
#' on-disk cache, and -- narrowed to the given \code{edges} when supplied --
#' the API keys, network services, and binaries those specific workflow steps
#' need. Machine-readable: the same report is what the generated script's
#' Step 0 uses to decide whether to stop before running anything, and what a
#' future \code{workflow_engine()} will inject into its prompts.
#'
#' Key checks report set/unset only -- a key's \strong{value} is never
#' printed, logged, or returned. All checks are local/no-network except the
#' \code{"network"} category, which is skipped (\code{status = "skip"})
#' when \code{getOption("TaxaWizard.offline")} is \code{TRUE}.
#'
#' @param edges Character vector of edge ids from
#'   \code{inst/graph/workflow_graph.json}, or \code{NULL} (default) for
#'   every edge in the graph. Narrows the \code{"key"}/\code{"network"}/
#'   \code{"binary"} rows to the union of those edges' \code{requires}
#'   tokens (plus one implied network check per key GROUP used); the
#'   \code{"r"}, \code{"package"}, and \code{"cache"} rows are always
#'   reported in full regardless of \code{edges}. Unknown edge ids are
#'   dropped with a warning.
#' @param verbose Logical (default \code{TRUE}). Print the report via
#'   \code{\link{print.taxaid_check}} before returning it.
#'
#' @return A data.frame (invisibly), class \code{"taxaid_check"}, with
#'   columns \code{component}, \code{category} (one of \code{"r"},
#'   \code{"package"}, \code{"key"}, \code{"network"}, \code{"cache"},
#'   \code{"binary"}), \code{status} (one of \code{"ok"}, \code{"missing"},
#'   \code{"warn"}, \code{"skip"}), \code{detail}, and \code{fix}.
#'
#' @seealso \code{\link{sniff_input}}
#' @export
#' @examples
#' \dontrun{
#' workflow_check()
#' workflow_check(edges = "seq_to_match")
#' options(TaxaWizard.offline = TRUE)
#' workflow_check(verbose = FALSE)
#' }
workflow_check <- function(edges = NULL, verbose = TRUE) {
  if (!is.null(edges) && (!is.character(edges) || length(edges) == 0L || anyNA(edges))) {
    stop("workflow_check: 'edges' must be a character vector of edge ids, or NULL.", call. = FALSE)
  }

  requirements <- .load_requirements()
  graph <- .load_graph()
  offline <- isTRUE(getOption("TaxaWizard.offline"))

  rows <- c(
    .check_r(),
    .check_packages(requirements),
    .check_cache()
  )

  tokens <- .selected_requires_tokens(graph, edges)
  for (tok in tokens) {
    row <- if (startsWith(tok, "key:")) {
      .resolve_key_token(tok, requirements)
    } else if (startsWith(tok, "net:")) {
      .resolve_net_token(tok, requirements, offline)
    } else if (startsWith(tok, "bin:")) {
      .resolve_bin_token(tok, requirements)
    } else if (startsWith(tok, "pkg:")) {
      .resolve_pkg_token(tok, requirements)
    } else {
      .check_row(tok, "key", "skip", "unrecognized requirement token prefix")
    }
    rows[[length(rows) + 1L]] <- row
  }

  out <- .rows_to_df(rows)
  out <- out[!duplicated(out[c("component", "category")]), , drop = FALSE]

  cat_order <- c("r", "package", "cache", "key", "network", "binary")
  out <- out[order(match(out$category, cat_order)), , drop = FALSE]
  rownames(out) <- NULL

  class(out) <- c("taxaid_check", class(out))
  if (isTRUE(verbose)) {
    print(out)
  }
  invisible(out)
}


#' Print Method for \code{workflow_check()} Reports
#'
#' Compact, grouped-by-category table; the \code{fix} text is shown for
#' every non-\code{"ok"} row so the output is directly actionable.
#'
#' @param x A \code{"taxaid_check"} data.frame from \code{\link{workflow_check}}.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export
print.taxaid_check <- function(x, ...) {
  symbol <- c(ok = "OK", missing = "MISSING", warn = "WARN", skip = "skip")

  cat("TaxaWizard setup check\n")
  cat(strrep("-", 78), "\n", sep = "")

  for (cat_name in unique(x$category)) {
    sub <- x[x$category == cat_name, , drop = FALSE]
    cat(sprintf("\n[%s]\n", cat_name))
    for (i in seq_len(nrow(sub))) {
      r <- sub[i, ]
      label <- symbol[[r$status]] %||% r$status
      cat(sprintf("  %-8s %-26s %s\n", label, .tw_trunc(r$component, 26L), r$detail))
    }
  }

  bad <- x[x$status %in% c("missing", "warn") & nzchar(x$fix), , drop = FALSE]
  if (nrow(bad) > 0L) {
    cat("\nFixes:\n")
    for (i in seq_len(nrow(bad))) {
      r <- bad[i, ]
      cat(sprintf("  - [%s] %s: %s\n", r$status, r$component, r$fix))
    }
  }

  cat(strrep("-", 78), "\n", sep = "")
  cat(sprintf(
    "%d missing, %d warn, %d ok, %d skip\n",
    sum(x$status == "missing"), sum(x$status == "warn"),
    sum(x$status == "ok"), sum(x$status == "skip")
  ))

  invisible(x)
}


# ==============================================================================
# sniff_input()
# ==============================================================================

#' Data-Format Extensions \code{sniff_input()} Actually Understands
#'
#' Single source of truth for what counts as a "data file" for auto-sniffing:
#' every extension listed here has a real, content-aware branch in
#' \code{.sniff_file()} (tabular / FASTA / \code{.rds} / JSON). Nothing else
#' does -- an \code{.xlsx} or \code{.Rdata} mention, for instance, is NOT on
#' this list, because \code{.sniff_file()} has no branch that actually parses
#' either format (they fall through to the generic "not a recognized
#' extension" result). \code{.detect_paths_in_text()}'s automatic scan of raw
#' chat text uses this SAME constant to decide what even counts as a
#' candidate for auto-sniffing, so the two can never drift apart.
#' @noRd
.SNIFF_DATA_EXTS <- c(
  "csv", "tsv", "txt", "tab", "dat", # tabular, via .sniff_header_row()
  "fasta", "fa", "fna", "fas", # FASTA
  "rds", # DADA2 seqtab / data.frame -- size-capped, see .SNIFF_SIZE_CAP
  "json" # SpeciesNet / iNaturalist CV
)

#' Byte Cap Shared by Every Content Peek
#'
#' Used both by \code{.peek_lines()} (text/CSV/JSON) and, for \code{.rds}
#' files, as the \code{file.size()} gate checked BEFORE \code{readRDS()} is
#' ever called -- \code{readRDS()} on an untrusted file has no size limit of
#' its own and deserializes the whole object before anything can inspect it,
#' so a file over this cap is described by size and name only, never loaded.
#' @noRd
.SNIFF_SIZE_CAP <- 1000000L

#' Placeholder Binding So \code{readRDS()} Can Be Mocked in Tests
#'
#' \code{testthat::local_mocked_bindings()} can only replace a base function
#' called unqualified from this package if the package namespace already has
#' SOME binding of that name (it is locked once installed, so a new one can't
#' be created at test time) -- a \code{NULL} binding is invisible to normal
#' function-call lookup (R skips a non-function when resolving a call's
#' head), so this has no effect outside a test that deliberately reassigns
#' it. See testthat's "Base functions" mocking docs.
#' @noRd
readRDS <- NULL

#' Does a character vector "look like" DNA sequence strings?
#' @noRd
.looks_like_dna <- function(x) {
  x <- x[!is.na(x) & nzchar(x)]
  if (length(x) == 0L) {
    return(FALSE)
  }
  mean(grepl("^[ACGTNacgtn]+$", x)) > 0.9
}

#' Read up to 1 MB / 50 lines of a file as text, without erroring.
#' @noRd
.peek_lines <- function(path, n_lines = 50L, max_bytes = .SNIFF_SIZE_CAP) {
  tryCatch(
    {
      con <- file(path, open = "rb")
      on.exit(close(con), add = TRUE)
      raw <- readBin(con, what = "raw", n = max_bytes)
      raw <- raw[raw != as.raw(0)] # binary files: strip embedded NULs so rawToChar doesn't error
      if (length(raw) == 0L) {
        return(character(0))
      }
      txt <- tryCatch(rawToChar(raw), error = function(e) "")
      if (!nzchar(txt)) {
        return(character(0))
      }
      # useBytes = TRUE: binary-garbage input may not be valid text in the
      # current locale's encoding; splitting byte-wise (rather than via a
      # locale-aware wide-character translation) avoids a warning/error on
      # a genuinely non-text file, which sniff_input() must never raise.
      Encoding(txt) <- "unknown"
      lines <- suppressWarnings(strsplit(txt, "\r\n|\n|\r", useBytes = TRUE)[[1]])
      utils::head(lines, n_lines)
    },
    error = function(e) character(0)
  )
}

#' Sniff a header-row CSV/TSV against known TaxaWizard input signatures
#' @noRd
.sniff_header_row <- function(first_line) {
  delim <- if (lengths(regmatches(first_line, gregexpr("\t", first_line))) >=
    lengths(regmatches(first_line, gregexpr(",", first_line)))) {
    "\t"
  } else {
    ","
  }
  header <- trimws(strsplit(first_line, delim, fixed = TRUE)[[1]])
  header_lower <- tolower(header)

  birdnet_cols <- c("start (s)", "end (s)", "scientific name", "common name", "confidence")
  birdnet_mangled <- c("start..s.", "end..s.", "scientific.name", "common.name", "confidence")
  if (all(birdnet_cols %in% header_lower) || all(birdnet_mangled %in% header_lower)) {
    return(list(
      node_id = "birdnet_detections", confidence = "high",
      evidence = "header matches BirdNET-Analyzer CSV columns (Start (s), End (s), Scientific name, Common name, Confidence) -- read_birdnet_output()"
    ))
  }

  if ("filename" %in% header_lower &&
    any(c("prediction", "pred1") %in% header_lower) &&
    any(c("confidence", "score1") %in% header_lower)) {
    return(list(
      node_id = "image_classifier_output", confidence = "high",
      evidence = "header has FileName + prediction/confidence (or pred1/score1) columns -- Animl CSV (read_animl_output())"
    ))
  }

  lat_names <- c("decimallatitude", "latitude", "lat", "y", "ylat")
  lon_names <- c("decimallongitude", "longitude", "lon", "long", "x", "xlon")
  has_lat <- any(lat_names %in% header_lower)
  has_lon <- any(lon_names %in% header_lower)
  if (has_lat && has_lon) {
    return(list(
      node_id = "occurrences", confidence = "high",
      evidence = sprintf(
        "header has coordinate columns (%s) -- occurrence records",
        paste(intersect(header_lower, c(lat_names, lon_names)), collapse = ", ")
      )
    ))
  }

  rank_cols <- c("kingdom", "phylum", "class", "order", "family", "genus", "species", "taxon_name")
  score_cols <- c("score", "pident", "confidence", "score_original", "match_score")
  has_rank <- any(rank_cols %in% header_lower)
  has_score <- any(score_cols %in% header_lower)

  if ("image_path" %in% header_lower && has_rank) {
    return(list(
      node_id = "images_meta", confidence = "high",
      evidence = "header has image_path + taxonomy columns -- reference image ground-truth labels"
    ))
  }

  if (has_score && has_rank) {
    return(list(
      node_id = "match_df", confidence = "high",
      evidence = sprintf(
        "header has a score-like column (%s) and taxon/rank column(s) (%s) -- standardized match data",
        paste(intersect(header_lower, score_cols), collapse = ", "),
        paste(intersect(header_lower, rank_cols), collapse = ", ")
      )
    ))
  }

  if (has_rank && !has_score) {
    n_rank <- length(intersect(header_lower, rank_cols))
    if ("observation_id" %in% header_lower || length(header) > n_rank + 3L) {
      return(list(
        node_id = "consensus_df", confidence = "medium",
        evidence = "header has taxon/rank columns, no score column, and observation-level columns -- looks like a pre-existing consensus table"
      ))
    }
    return(list(
      node_id = "taxa", confidence = "high",
      evidence = sprintf(
        "header has taxon/rank column(s) (%s) and no score column -- taxon list",
        paste(intersect(header_lower, rank_cols), collapse = ", ")
      )
    ))
  }

  if (length(header) == 1L) {
    # A single "column" here may just as well be the file's first line of
    # actual content (a headerless list, a credential, a config line) as a
    # real column name -- .sniff_header_row() cannot tell the two apart, so
    # the value itself is never echoed into evidence, only its shape.
    return(list(
      node_id = "taxa", confidence = "medium",
      evidence = "single-column file (value not shown) -- likely a plain taxon-name list"
    ))
  }

  # Same reasoning: these "header" fields are unclassified and may be
  # arbitrary file content, not column names -- report the count, never the
  # values.
  list(
    node_id = NA_character_, confidence = "low",
    evidence = sprintf("could not classify; %d column(s) detected (values not shown)", length(header))
  )
}

#' Sniff a single (non-directory) file
#' @noRd
.sniff_file <- function(path) {
  ext <- tolower(tools::file_ext(path))

  # --- .rds: DADA2 seqtab matrix, or fall through to the header sniffer for a data.frame ---
  if (identical(ext, "rds")) {
    # Unlike every other branch (capped via .peek_lines()'s .SNIFF_SIZE_CAP),
    # readRDS() has no built-in limit and deserializes the whole object
    # before anything can inspect it -- readRDS() on an untrusted file is a
    # known-risky operation (delayed-evaluation promises can run code when
    # the deserialized object is later touched). A file over the cap is
    # described by size and name only; it is never loaded.
    fsize <- suppressWarnings(file.size(path))
    if (!is.na(fsize) && fsize > .SNIFF_SIZE_CAP) {
      return(list(
        node_id = NA_character_, confidence = "low",
        evidence = sprintf(
          ".rds file '%s' is %.1f MB, over the %.0f KB inspection cap -- reported by size and name only, not loaded",
          basename(path), fsize / 1024^2, .SNIFF_SIZE_CAP / 1024
        )
      ))
    }
    obj <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.null(obj)) {
      return(list(node_id = NA_character_, confidence = "low", evidence = "not a readable .rds file"))
    }
    if (is.matrix(obj) && !is.null(colnames(obj)) && .looks_like_dna(colnames(obj))) {
      return(list(
        node_id = "sequences", confidence = "high",
        evidence = sprintf(
          ".rds matrix (%d x %d) with DNA-sequence column names -- DADA2 seqtab", nrow(obj), ncol(obj)
        )
      ))
    }
    if (is.data.frame(obj) && length(names(obj)) > 0L) {
      out <- .sniff_header_row(paste(names(obj), collapse = ","))
      out$evidence <- paste0(".rds data.frame; ", out$evidence)
      return(out)
    }
    return(list(
      node_id = NA_character_, confidence = "low",
      evidence = sprintf(".rds object of class %s not recognized", paste(class(obj), collapse = "/"))
    ))
  }

  peek <- .peek_lines(path)
  if (length(peek) == 0L) {
    return(list(node_id = NA_character_, confidence = "low", evidence = "empty or unreadable file"))
  }
  first_line <- peek[[1]]

  # --- FASTA (raw sequences, or a reference FASTA + sibling taxonomy TSV) ---
  if (ext %in% c("fasta", "fa", "fna", "fas") || startsWith(trimws(first_line), ">")) {
    stem <- tools::file_path_sans_ext(path)
    sib <- Filter(file.exists, paste0(stem, c(".tsv", ".txt", ".csv")))
    if (length(sib) > 0L) {
      sib_first <- tryCatch(readLines(sib[[1]], n = 1L, warn = FALSE), error = function(e) "")
      if (length(sib_first) > 0L && grepl("composite_id", sib_first, ignore.case = TRUE)) {
        return(list(
          node_id = "local_fasta", confidence = "high",
          evidence = sprintf(
            "FASTA with a sibling taxonomy file '%s' (composite_id header) -- read_reference_fasta() taxonomy_file format",
            basename(sib[[1]])
          )
        ))
      }
    }
    return(list(
      node_id = "sequences", confidence = "high",
      evidence = "FASTA file (starts with '>') -- read_sequence_table()"
    ))
  }

  # --- CRABS internal format: headerless, 11 tab-delimited fields, last one a DNA sequence ---
  fields <- strsplit(first_line, "\t", fixed = TRUE)[[1]]
  if (length(fields) == 11L && .looks_like_dna(fields[11])) {
    return(list(
      node_id = "local_fasta", confidence = "high",
      evidence = "headerless 11-column tab-delimited file ending in a DNA sequence -- CRABS internal format (read_crabs_output())"
    ))
  }

  # --- JSON: SpeciesNet ("predictions") or iNaturalist CV ("results"/"taxon") ---
  looks_json <- identical(ext, "json") || grepl("^\\s*[{\\[]", first_line)
  if (looks_json) {
    fsize <- suppressWarnings(file.size(path))
    parsed <- NULL
    if (!is.na(fsize) && fsize <= 1000000L) {
      parsed <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) NULL)
    }
    if (!is.null(parsed) && is.list(parsed)) {
      if (!is.null(parsed$predictions)) {
        return(list(
          node_id = "image_classifier_output", confidence = "high",
          evidence = "JSON with top-level 'predictions' array -- SpeciesNet predictions_json (read_speciesnet_output())"
        ))
      }
      if (!is.null(parsed$results)) {
        first_res <- if (length(parsed$results) > 0L) parsed$results[[1]] else NULL
        if (!is.null(first_res) && !is.null(first_res$taxon)) {
          return(list(
            node_id = "image_classifier_output", confidence = "high",
            evidence = "JSON with top-level 'results' array of {taxon: ...} objects -- iNaturalist CV API response (read_inaturalist_cv_output())"
          ))
        }
      }
    }
    text <- paste(peek, collapse = "\n")
    if (grepl('"predictions"\\s*:', text)) {
      return(list(
        node_id = "image_classifier_output", confidence = "medium",
        evidence = "raw text contains a top-level 'predictions' key -- looks like SpeciesNet JSON but could not be fully parsed"
      ))
    }
    if (grepl('"results"\\s*:', text) && grepl('"taxon"\\s*:', text)) {
      return(list(
        node_id = "image_classifier_output", confidence = "medium",
        evidence = "raw text contains 'results'/'taxon' keys -- looks like iNaturalist CV JSON but could not be fully parsed"
      ))
    }
    return(list(
      node_id = NA_character_, confidence = "low",
      evidence = "JSON file with no recognized 'predictions' or 'results' top-level key"
    ))
  }

  # --- Delimited text with a header row ---
  # Restricted to plausible tabular-data extensions (or none at all, e.g. a
  # file uploaded/saved without one) so an arbitrary text file -- an R
  # script, markdown, a log -- doesn't get confidently misread as a
  # single-column taxon list just because its first line has no delimiter.
  tabular_exts <- c("csv", "tsv", "txt", "tab", "dat")
  if (!(identical(ext, "") || ext %in% tabular_exts)) {
    return(list(
      node_id = NA_character_, confidence = "low",
      evidence = sprintf(
        "'.%s' is not a recognized tabular/FASTA/JSON/rds input extension", ext
      )
    ))
  }
  .sniff_header_row(first_line)
}

#' Sniff a directory: infer from the first (or first BirdNET-looking) file inside
#' @noRd
.sniff_dir <- function(path) {
  files <- list.files(path, full.names = TRUE, recursive = FALSE)
  files <- files[!dir.exists(files)]
  if (length(files) == 0L) {
    return(list(node_id = NA_character_, confidence = "low", evidence = sprintf("directory '%s' has no files", path)))
  }

  pick <- files[1L]
  birdnet_like <- grep("BirdNET\\.results\\.csv$", files, ignore.case = TRUE, value = TRUE)
  if (length(birdnet_like) > 0L) pick <- birdnet_like[1L]

  inner <- tryCatch(.sniff_file(pick), error = function(e) NULL)
  if (is.null(inner) || is.na(inner$node_id)) {
    return(list(
      node_id = NA_character_, confidence = "low",
      evidence = sprintf("directory with %d file(s); could not classify from '%s'", length(files), basename(pick))
    ))
  }

  downgrade <- c(high = "medium", medium = "low", low = "low")
  list(
    node_id = inner$node_id, confidence = unname(downgrade[inner$confidence]),
    evidence = sprintf(
      "directory with %d file(s); inferred from '%s': %s", length(files), basename(pick), inner$evidence
    )
  )
}


#' Guess Which Input Node a File Looks Like
#'
#' Sniffs a file's extension and header/content signature against the real
#' header formats the ecosystem's \code{read_*()} ingest functions expect
#' (\code{TaxaMatch::read_sequence_table()}, \code{read_birdnet_output()},
#' \code{read_animl_output()}, \code{read_inaturalist_cv_output()},
#' \code{read_speciesnet_output()}; \code{TaxaLikely::read_crabs_output()},
#' \code{read_reference_fasta()}), so a user (or the future chat engine) can
#' point at a path and get back which of \code{workflow_graph.json}'s input
#' node ids it most likely is.
#'
#' Reads at most the first 50 lines / 1 MB of the file (\code{.SNIFF_SIZE_CAP}).
#' A \code{.rds} file over that same cap is reported by its size and name
#' only -- it is never deserialized, since \code{readRDS()} has no size limit
#' of its own and is a known-risky operation on an untrusted file. Never
#' errors on an unreadable, empty, or binary-garbage file -- it returns
#' \code{node_id = NA} with an explanatory \code{evidence} string instead.
#' \code{evidence} never contains a verbatim content sample: for a recognized
#' schema it reports the matched column names (from a fixed, known
#' vocabulary); for an unclassifiable or single-column file it reports the
#' shape (column/value count) only, never the value, since for a file with no
#' recognized header the "column" may just be that file's actual first line
#' of content.
#'
#' Calling \code{sniff_input(path)} directly with a path you name is a
#' deliberate act and is not further restricted. This is distinct from
#' TaxaWizard's own automatic wiring of it into the chat engine's classify
#' prompt (\code{.detect_paths_in_text()} + \code{.format_sniff_block()},
#' \code{R/graph.R}), which scans raw, untrusted chat text for existing paths
#' and must not auto-sniff just anything mentioned: it auto-sniffs only a
#' path whose extension is on \code{.SNIFF_DATA_EXTS} (the formats this
#' function actually understands), containing no dotfile/dotdir path segment,
#' and either under the working directory/session \code{tempdir()} or
#' explicitly quoted by the user and outside \code{/etc}, \code{/private},
#' \code{/var}, \code{/usr}, \code{/System}, \code{/Library}, or the user's
#' home directory itself -- see \code{.sniff_path_allowed()}.
#'
#' @param path Character scalar. Path to a file, or a directory (in which
#'   case the first file inside -- preferring one that looks like a BirdNET
#'   result CSV -- is sniffed and the confidence is downgraded one level,
#'   since only one file of a possibly-mixed directory was inspected).
#'
#' @return A list with:
#' \describe{
#'   \item{\code{node_id}}{One of the input node ids in
#'     \code{workflow_graph.json} (see \code{TaxaWizard:::.list_node_types()$inputs}),
#'     or \code{NA_character_} when unrecognized.}
#'   \item{\code{confidence}}{One of \code{"high"}, \code{"medium"}, \code{"low"}.}
#'   \item{\code{evidence}}{Character scalar explaining the call.}
#' }
#' @seealso \code{\link{workflow_check}}
#' @export
#' @examples
#' tmp <- tempfile(fileext = ".fasta")
#' writeLines(c(">ASV_001", "ACGTACGTACGT"), tmp)
#' sniff_input(tmp)
#' unlink(tmp)
#'
#' # A non-DNA input sniffs the same way (a BirdNET-Analyzer detections CSV)
#' tmp_acoustic <- tempfile(fileext = ".csv")
#' writeLines(c(
#'   "Start (s),End (s),Scientific name,Common name,Confidence",
#'   "0.0,3.0,Turdus migratorius,American Robin,0.87"
#' ), tmp_acoustic)
#' sniff_input(tmp_acoustic)
#' unlink(tmp_acoustic)
sniff_input <- function(path) {
  tryCatch(
    {
      if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
        return(list(
          node_id = NA_character_, confidence = "low",
          evidence = "'path' must be a single non-empty file path"
        ))
      }
      if (!file.exists(path)) {
        return(list(
          node_id = NA_character_, confidence = "low",
          evidence = sprintf("file not found: %s", path)
        ))
      }
      if (dir.exists(path)) {
        return(.sniff_dir(path))
      }
      .sniff_file(path)
    },
    error = function(e) {
      list(
        node_id = NA_character_, confidence = "low",
        evidence = sprintf("error while sniffing '%s': %s", path, conditionMessage(e))
      )
    }
  )
}


# ==============================================================================
# Rendering setup state into LLM prompts
#
# The LLM never sees a taxaid_check data.frame; it sees the text these build.
# Two rules shape them. (1) Only non-ok rows carry information the model can
# act on -- an edges-scoped check still returns every base row (R version, the
# eight packages, cache), so injecting the whole table would spend ~26 lines to
# say "fine" and bury the one line that is not. (2) Statuses are reported, never
# secrets: a key row says "set / unset", never the value.
#
# A third rule governs the auto-sniff wiring below (.detect_paths_in_text() +
# .format_sniff_block(), called from graph.R's classify-phase prompt): raw
# chat text is untrusted input, so a bare mention of an existing path is NOT
# by itself enough to have that file's content read and injected into the
# prompt. Only a path whose extension is on .SNIFF_DATA_EXTS, containing no
# dotfile/dotdir segment, and either under the working directory/tempdir() or
# explicitly quoted (and outside .SNIFF_SYSTEM_ROOTS) is auto-sniffed -- see
# .sniff_path_allowed(). What .format_sniff_block() then injects is
# sniff_input()'s structural summary (node_id/confidence/evidence), never a
# raw content sample: .sniff_header_row()'s single-column and
# could-not-classify branches report shape only (column/value counts), never
# the values themselves, because for an unrecognized file "the header" may
# just be that file's actual first line of content.
# ==============================================================================

#' Session Cache for the Full Setup Check
#'
#' \code{workflow_check()} re-reads requirements.json, the graph, and the
#' environment on every call. The classify phase needs the same full report on
#' every turn of a conversation, so it is computed once per session here.
#' \code{workflow_create()} seeds this cache, which is also why the user sees
#' the same report the LLM is being given rather than a second, separate run.
#'
#' @noRd
.setup_cache <- new.env(parent = emptyenv())

#' @param refresh Logical. Recompute even if cached.
#' @return A \code{taxaid_check} data.frame.
#' @noRd
.session_setup_check <- function(refresh = FALSE) {
  if (isTRUE(refresh) || is.null(.setup_cache$full)) {
    .setup_cache$full <- workflow_check(verbose = FALSE)
  }
  .setup_cache$full
}


#' Render a Setup Check as Prompt Text
#'
#' @param chk A \code{taxaid_check} data.frame from \code{workflow_check()}.
#' @param all_ok_note Character. Text to emit when nothing needs attention.
#' @return Character string.
#' @noRd
.format_check_block <- function(chk, all_ok_note = "Everything this workflow needs is present.") {
  if (is.null(chk) || !is.data.frame(chk) || nrow(chk) == 0L) {
    return("(setup was not checked)")
  }

  n_missing <- sum(chk$status == "missing")
  n_warn <- sum(chk$status == "warn")
  n_ok <- sum(chk$status == "ok")
  summary_line <- sprintf(
    "%d ok, %d warn, %d missing.", n_ok, n_warn, n_missing
  )

  notable <- chk[chk$status %in% c("missing", "warn"), , drop = FALSE]
  if (nrow(notable) == 0L) {
    return(paste(summary_line, all_ok_note))
  }

  rows <- vapply(seq_len(nrow(notable)), function(i) {
    fix <- notable$fix[i]
    fix <- if (is.na(fix) || !nzchar(fix)) "" else paste0(" -- fix: ", fix)
    sprintf(
      "- %s [%s]: %s%s",
      notable$component[i], notable$status[i],
      if (is.na(notable$detail[i]) || !nzchar(notable$detail[i])) "(no detail)" else notable$detail[i],
      fix
    )
  }, "")

  paste0(summary_line, "\n", paste(rows, collapse = "\n"))
}


#' Is This Path's Extension One \code{sniff_input()} Actually Understands?
#' @noRd
.sniff_ext_allowed <- function(path) {
  ext <- tolower(tools::file_ext(path))
  nzchar(ext) && ext %in% .SNIFF_DATA_EXTS
}

#' Does Any Path Segment Start With "." (a Dotfile, or Inside a Dotdir)?
#'
#' Catches \code{.Renviron}, anything under \code{.ssh/}, \code{.aws/}, etc.
#' @noRd
.sniff_has_dot_segment <- function(path) {
  segs <- strsplit(gsub("\\\\", "/", path), "/", fixed = TRUE)[[1]]
  any(nzchar(segs) & startsWith(segs, "."))
}

#' Is \code{path} At or Below \code{root}? (Both Already Normalized)
#' @noRd
.sniff_path_under <- function(path, root) {
  if (!nzchar(root)) {
    return(FALSE)
  }
  path <- sub("/+$", "", path)
  root <- sub("/+$", "", root)
  identical(path, root) || startsWith(path, paste0(root, "/"))
}

#' System Roots an Auto-Sniffed Path Must Never Resolve Under
#'
#' Applies even to an explicitly quoted path -- quoting only exempts a path
#' from the working-directory/tempdir() scoping requirement below, never
#' from this list.
#' @noRd
.SNIFF_SYSTEM_ROOTS <- c("/etc", "/private", "/var", "/usr", "/System", "/Library")

#' Confidentiality Gate for Auto-Sniffing a Path Found in Raw Chat Text
#'
#' This is a confidentiality boundary, not a false-positive filter: a bare
#' mention of an existing file's path anywhere on disk must never have its
#' content read and injected into an LLM prompt just because the text
#' happened to contain that path. All of the following must hold:
#' \enumerate{
#'   \item its extension is on \code{.SNIFF_DATA_EXTS};
#'   \item no path segment is a dotfile/dotdir;
#'   \item it is not the user's home directory itself;
#'   \item it is under the current working directory or R's own session
#'     \code{tempdir()} (both are scratch space this session already
#'     controls) -- OR it was named via an explicit quote/backtick (an
#'     explicit act) AND does not resolve under \code{.SNIFF_SYSTEM_ROOTS}.
#' }
#'
#' @param path An existing, already \code{path.expand()}-ed path.
#' @param explicit Was this path named via a quote/backtick, as opposed to a
#'   bare mention?
#' @noRd
.sniff_path_allowed <- function(path, explicit) {
  if (!.sniff_ext_allowed(path)) {
    return(FALSE)
  }
  if (.sniff_has_dot_segment(path)) {
    return(FALSE)
  }

  norm_path <- suppressWarnings(normalizePath(path, winslash = "/", mustWork = FALSE))
  norm_home <- suppressWarnings(normalizePath(path.expand("~"), winslash = "/", mustWork = FALSE))
  if (identical(sub("/+$", "", norm_path), sub("/+$", "", norm_home))) {
    return(FALSE)
  }

  cwd <- suppressWarnings(normalizePath(getwd(), winslash = "/", mustWork = FALSE))
  tdir <- suppressWarnings(normalizePath(tempdir(), winslash = "/", mustWork = FALSE))
  if (.sniff_path_under(norm_path, cwd) || .sniff_path_under(norm_path, tdir)) {
    return(TRUE)
  }

  if (!isTRUE(explicit)) {
    return(FALSE)
  }
  !any(vapply(.SNIFF_SYSTEM_ROOTS, function(r) .sniff_path_under(norm_path, r), logical(1)))
}

#' Find Existing Paths Mentioned in a User Message
#'
#' Only paths that EXIST are returned: the point is to sniff real data, and a
#' path the user typed from memory (or an example path out of the prompt pack)
#' must not be reported to the model as though it had been inspected. Quoted
#' strings (including backtick-quoted) are preferred because they are
#' unambiguous and count as an explicit act; bare tokens are accepted when
#' they look like a path and resolve.
#'
#' A path surviving the existence check must further pass
#' \code{\link{.sniff_path_allowed}} -- see its docstring for the exact
#' confidentiality rule (extension allow-list, no dotfiles/dotdirs, and
#' scoped to the working directory/session tempdir, or an explicitly quoted
#' path outside the system directories).
#'
#' @param txt Character. One user message.
#' @param max_paths Integer. Cap on how many paths to report.
#' @return Character vector of existing, in-scope paths (possibly empty).
#' @noRd
.detect_paths_in_text <- function(txt, max_paths = 3L) {
  if (!is.character(txt) || length(txt) != 1L || is.na(txt) || !nzchar(txt)) {
    return(character(0))
  }

  explicit_cands <- character(0)
  implicit_cands <- character(0)

  # (1) Quoted / backtick-quoted strings are an explicit act -- unambiguous,
  # take them whole, spaces and all.
  quoted <- unlist(regmatches(txt, gregexpr('"[^"]+"|\'[^\']+\'|`[^`]+`', txt)))
  explicit_cands <- c(explicit_cands, gsub('^["\'`]|["\'`]$', "", quoted))

  # (2) Bare tokens containing no whitespace -- catches extensionless/no-slash
  # mentions; the extension allow-list in .sniff_path_allowed() is what
  # actually adjudicates whether any of these are auto-sniffed.
  implicit_cands <- c(implicit_cands, unlist(regmatches(
    txt,
    gregexpr("[^\\s\"',;()]*(?:/|\\\\)[^\\s\"',;()]*", txt, perl = TRUE)
  )))

  # (3) Paths CONTAINING SPACES, unquoted. A no-whitespace rule alone silently
  # misses almost every real path through a folder like Google Drive's default
  # "My Drive": an unquoted path through it is never sniffed, so
  # {{SNIFF_RESULT}} degrades to "nothing was inspected" while the file
  # sits right there.
  #
  # Anchor on an extension sniff_input() actually understands, then offer
  # EVERY plausible start ('/' or '~') at or before it as a candidate,
  # longest first. Generous candidates, strict filter: file.exists() below
  # is what actually adjudicates, so an over-long candidate that swallowed
  # preceding prose simply fails to exist.
  ext_re <- paste0("\\.(?:", paste(.SNIFF_DATA_EXTS, collapse = "|"), ")")
  ends <- gregexpr(ext_re, txt, perl = TRUE, ignore.case = TRUE)[[1L]]
  if (ends[1L] != -1L) {
    lens <- attr(ends, "match.length")
    starts <- gregexpr("[~/]", txt, perl = TRUE)[[1L]]
    if (starts[1L] != -1L) {
      for (i in seq_along(ends)) {
        stop_at <- ends[i] + lens[i] - 1L
        for (st in starts[starts <= stop_at]) {
          implicit_cands <- c(implicit_cands, substr(txt, st, stop_at))
        }
      }
    }
  }

  # (4) Trailing sentence punctuation is not part of a filename.
  strip_trailing_punct <- function(x) sub("[.,;:!?)\\]]+$", "", x)
  explicit_cands <- strip_trailing_punct(explicit_cands)
  implicit_cands <- strip_trailing_punct(implicit_cands)

  existing_of <- function(cands) {
    cands <- unique(cands[nzchar(cands)])
    if (length(cands) == 0L) {
      return(character(0))
    }
    expanded <- suppressWarnings(path.expand(cands))
    exists <- vapply(expanded, function(p) {
      isTRUE(tryCatch(file.exists(p), error = function(e) FALSE))
    }, TRUE)
    unique(expanded[exists])
  }

  explicit_hits <- existing_of(explicit_cands)
  implicit_hits <- existing_of(implicit_cands)

  out <- character(0)
  for (p in explicit_hits) {
    if (.sniff_path_allowed(p, explicit = TRUE)) out <- c(out, p)
  }
  for (p in implicit_hits) {
    if (!(p %in% out) && .sniff_path_allowed(p, explicit = FALSE)) out <- c(out, p)
  }

  out <- unique(out)
  # Longest first: a real path beats a suffix of itself that also happens to
  # exist (e.g. "/Users" inside "/Users/x/My Data.rds").
  out <- out[order(nchar(out), decreasing = TRUE)]
  utils::head(out, max_paths)
}


#' Render sniff_input() Results for the Classify Prompt
#'
#' @param paths Character vector of existing paths.
#' @return Character string.
#' @noRd
.format_sniff_block <- function(paths) {
  if (length(paths) == 0L) {
    return(paste(
      "No path in the user's message was found on disk, so nothing was inspected.",
      "Ask the user for the path rather than guessing the input type from prose."
    ))
  }

  rows <- vapply(paths, function(p) {
    s <- sniff_input(p)
    node <- s$node_id
    if (is.null(node) || is.na(node)) {
      sprintf("- `%s`: could not be classified (%s)", p, s$evidence %||% "no evidence")
    } else {
      sprintf(
        "- `%s` -> node_id `%s` (confidence: %s; evidence: %s)",
        p, node, s$confidence %||% "unknown", s$evidence %||% ""
      )
    }
  }, "")

  paste0(
    "sniff_input() inspected the path(s) the user named:\n",
    paste(rows, collapse = "\n")
  )
}
