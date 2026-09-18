# ==============================================================================
# registry.R
# TaxaWizard -- introspected function registry
#
# Replaces the hand-maintained, per-package JSON metadata files (removed
# 2026-09-18, see CLAUDE.md top note). Every function signature, parameter, title,
# description, and return-value note is derived at runtime from the INSTALLED
# TaxaID packages via getNamespaceExports()/formals()/tools::Rd_db() -- never
# hand-typed here. DERIVE, DON'T DECLARE (see
# ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md, section P1).
# ==============================================================================

#' TaxaID Packages (Dependency Order)
#'
#' The single, authoritative list of TaxaID ecosystem packages TaxaWizard
#' knows how to introspect. Nothing else in this package hard-codes this
#' list -- every consumer (registry, engine, graph, create) either takes
#' \code{TAXAID_PACKAGES} as a default or receives an already-built registry.
#'
#' @noRd
TAXAID_PACKAGES <- c(
  "TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
  "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag"
)


#' Registry Cache Schema Version
#'
#' Bumped whenever the SHAPE or the PARSING of a registry entry changes.
#' The cache is keyed on the package's version and Built timestamp, neither
#' of which moves when TaxaWizard's own extraction code changes -- so
#' without this, improving the Rd parser would leave every existing cache
#' file serving the old, worse text forever (and a user who never clears
#' the cache would never see the fix). Part of the cache file name.
#'
#' 2: structural \arguments parsing (was: re-parsed Rd2txt output).
#'
#' @noRd
REGISTRY_SCHEMA <- 2L


#' Build the Introspected Function Registry
#'
#' For each installed TaxaID package, introspects every exported function
#' (via \code{getNamespaceExports()}), its formal arguments (via
#' \code{formals()}), and its documentation (via \code{tools::Rd_db()}) to
#' build a registry the workflow engine can inject into LLM prompts and use
#' to validate generated code. This REPLACES the old hand-maintained,
#' per-package JSON metadata files -- the registry is always current with
#' whatever is actually installed, because it is read from the installed
#' packages themselves rather than typed by hand.
#'
#' Results are cached per package under
#' \code{tools::R_user_dir("TaxaWizard", "cache")}, keyed on both the
#' package's version AND its \code{packageDescription()$Built} timestamp
#' (all TaxaID packages currently report version \code{0.1.0}, so version
#' alone cannot distinguish a stale build from a fresh one).
#'
#' @param packages Character vector of package names to introspect. Default
#'   \code{NULL} uses \code{TAXAID_PACKAGES} (all 8 TaxaID packages, in
#'   dependency order). A package that is not installed is skipped with a
#'   message rather than raising an error.
#' @param refresh Logical. When \code{TRUE}, ignores any cached registry
#'   and rebuilds from the installed package, overwriting the cache.
#'   Default \code{FALSE}.
#'
#' @return A named list, one element per package that was found installed.
#'   Each element has components \code{package}, \code{version}, \code{built},
#'   and \code{functions} (a list, one entry per export, alphabetical by
#'   name, each with \code{name}, \code{title}, \code{description},
#'   \code{params} (a list of \code{name}/\code{required}/\code{default}/
#'   \code{doc}, in \code{formals()} order), and \code{value}).
#'
#' @export
#'
#' @examples
#' \dontrun{
#' reg <- workflow_registry()
#' reg$TaxaAssign$functions[[1]]$name
#'
#' # Force a rebuild for one package (e.g. after reinstalling it)
#' reg <- workflow_registry(packages = "TaxaAssign", refresh = TRUE)
#' }
workflow_registry <- function(packages = NULL, refresh = FALSE) {
  packages <- packages %||% TAXAID_PACKAGES
  cache_dir <- .registry_cache_dir()

  registry <- list()
  for (p in packages) {
    if (!requireNamespace(p, quietly = TRUE)) {
      message(
        "TaxaWizard: package '", p, "' is not installed -- ",
        "skipping from workflow_registry()."
      )
      next
    }

    version <- as.character(utils::packageVersion(p))
    built <- tryCatch(utils::packageDescription(p)$Built, error = function(e) NULL)
    if (is.null(built) || is.na(built) || !nzchar(built)) built <- "unknown"
    built_key <- gsub("[^0-9]", "", built)
    if (!nzchar(built_key)) built_key <- "0"
    cache_file <- file.path(
      cache_dir,
      sprintf("%s_%s_%s_v%d.rds", p, version, built_key, REGISTRY_SCHEMA)
    )

    entry <- NULL
    if (!refresh && file.exists(cache_file)) {
      entry <- tryCatch(readRDS(cache_file), error = function(e) NULL)
    }

    if (is.null(entry)) {
      entry <- .build_package_registry(p, version, built)
      tryCatch(
        {
          if (!dir.exists(cache_dir)) {
            dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
          }
          saveRDS(entry, cache_file)
          # Delete stale cache files for this package (old version/build).
          stale <- list.files(
            cache_dir,
            pattern = sprintf("^%s_.*\\.rds$", p), full.names = TRUE
          )
          stale <- setdiff(stale, cache_file)
          if (length(stale) > 0L) unlink(stale)
        },
        error = function(e) NULL
      )
    }

    registry[[p]] <- entry
  }

  registry
}


#' Registry Cache Directory
#' @noRd
.registry_cache_dir <- function() {
  file.path(tools::R_user_dir("TaxaWizard", "cache"), "registry")
}


#' Build One Package's Registry Entry from the Installed Package
#'
#' Introspects a single installed package: every non-internal export becomes
#' one function entry, with formals-derived parameters and (when available)
#' Rd-derived title/description/argument docs/value.
#'
#' @param pkg Character. Package name.
#' @param version Character. \code{packageVersion(pkg)} as a string.
#' @param built Character. \code{packageDescription(pkg)$Built}.
#' @return A list with \code{package}, \code{version}, \code{built},
#'   \code{functions}.
#' @noRd
.build_package_registry <- function(pkg, version, built) {
  exports <- getNamespaceExports(pkg)
  exports <- exports[!grepl("^\\.", exports)]
  exports <- Filter(function(nm) {
    val <- tryCatch(getExportedValue(pkg, nm), error = function(e) NULL)
    is.function(val)
  }, exports)
  exports <- sort(exports)

  rd_db <- tryCatch(tools::Rd_db(pkg), error = function(e) NULL)
  alias_map <- .rd_alias_map(rd_db)

  functions <- lapply(exports, function(fn_name) {
    fn <- getExportedValue(pkg, fn_name)
    rd_entry <- alias_map[[fn_name]]
    .build_function_entry(fn_name, fn, rd_entry)
  })

  list(package = pkg, version = version, built = built, functions = functions)
}


#' Map Rd Aliases to Their Parsed Rd Object
#'
#' Multiple exports can share one Rd file (\code{\alias}); this builds a
#' lookup from every alias name to that Rd file's parsed content so each
#' export can find its own documentation regardless of how many names alias
#' to the same page.
#'
#' @param rd_db Result of \code{tools::Rd_db(pkg)}, or \code{NULL}.
#' @return A named list: alias name -> Rd object.
#' @noRd
.rd_alias_map <- function(rd_db) {
  alias_map <- list()
  if (is.null(rd_db)) {
    return(alias_map)
  }
  for (rd_entry in rd_db) {
    tags <- vapply(rd_entry, function(x) attr(x, "Rd_tag") %||% "", character(1))
    alias_idx <- which(tags == "\\alias")
    for (i in alias_idx) {
      alias_name <- paste(unlist(rd_entry[[i]]), collapse = "")
      if (nzchar(alias_name)) alias_map[[alias_name]] <- rd_entry
    }
  }
  alias_map
}


#' Build One Function's Registry Entry
#'
#' @param fn_name Character. Exported function name.
#' @param fn The function object itself (\code{getExportedValue()}).
#' @param rd_entry Parsed Rd object for this function (from
#'   \code{.rd_alias_map()}), or \code{NULL} if no Rd documents it.
#' @return A list with \code{name}, \code{title}, \code{description},
#'   \code{params}, \code{value}.
#' @noRd
.build_function_entry <- function(fn_name, fn, rd_entry) {
  f <- formals(fn)
  param_names <- names(f)

  sections <- if (!is.null(rd_entry)) .rd_sections(rd_entry) else NULL
  arg_docs <- if (!is.null(sections)) sections$arguments else list()

  params <- lapply(param_names, function(nm) {
    is_required <- identical(f[[nm]], quote(expr = ))
    default <- if (is_required) NULL else paste(deparse(f[[nm]]), collapse = " ")
    list(
      name     = nm,
      required = is_required,
      default  = default,
      doc      = arg_docs[[nm]] %||% NULL
    )
  })

  list(
    name        = fn_name,
    title       = if (!is.null(sections)) sections$title else NULL,
    description = if (!is.null(sections)) sections$description else NULL,
    params      = params,
    value       = if (!is.null(sections)) sections$value else NULL
  )
}


#' Extract Title/Description/Arguments/Value from a Parsed Rd Object
#'
#' Renders just the \\title, \\description, and \\value sections (whichever
#' are present) via \code{tools::Rd2txt()}, then parses the rendered plain
#' text back into structured pieces. \\arguments is NOT rendered: it is read
#' structurally from the Rd tree by \code{.rd_arguments()}, because its
#' item/term structure is exact in the tree and only inferable (badly) from
#' the rendered text. Rendering only a
#' synthetic sub-document (rather than the whole Rd file) keeps \\examples,
#' \\details, and \\seealso -- often the largest sections -- out of the
#' registry entirely; \code{\link[tools]{Rd2txt}} requires \\name and
#' \\title to be present to render at all, so those two are always
#' included even though only \\title's text is kept.
#'
#' @param rd_entry Parsed Rd object (one package's one \code{.Rd} file).
#' @return A list with \code{title}, \code{description} (<= 600 chars,
#'   first paragraph only), \code{value} (<= 400 chars), and
#'   \code{arguments} (named list: parameter name -> doc text), or
#'   \code{NULL} if rendering failed.
#' @noRd
.rd_sections <- function(rd_entry) {
  tags <- vapply(rd_entry, function(x) attr(x, "Rd_tag") %||% "", character(1))
  get1 <- function(tag) {
    i <- which(tags == tag)
    if (length(i) > 0L) rd_entry[[i[1L]]] else NULL
  }

  name_tag <- get1("\\name")
  title_tag <- get1("\\title")
  if (is.null(name_tag) || is.null(title_tag)) {
    return(NULL)
  }
  desc_tag <- get1("\\description")
  args_tag <- get1("\\arguments")
  value_tag <- get1("\\value")

  doc <- list(name_tag, title_tag)
  doc_tags <- c("\\name", "\\title")
  if (!is.null(desc_tag)) {
    doc <- c(doc, list(desc_tag))
    doc_tags <- c(doc_tags, "\\description")
  }
  if (!is.null(value_tag)) {
    doc <- c(doc, list(value_tag))
    doc_tags <- c(doc_tags, "\\value")
  }
  for (i in seq_along(doc)) attr(doc[[i]], "Rd_tag") <- doc_tags[i]
  class(doc) <- "Rd"

  rd_lines <- tryCatch(
    withCallingHandlers(
      utils::capture.output(
        tools::Rd2txt(doc, options = list(underline_titles = FALSE))
      ),
      warning = function(w) invokeRestart("muffleWarning")
    ),
    error = function(e) NULL
  )
  if (is.null(rd_lines)) {
    return(NULL)
  }
  txt <- paste(rd_lines, collapse = "\n")

  sections <- .parse_rd_txt(txt)

  # \arguments is parsed STRUCTURALLY from the Rd tree, not from rendered
  # text -- see .rd_arguments().
  sections$arguments <- if (!is.null(args_tag)) .rd_arguments(args_tag) else list()
  sections
}


#' Parse Rd2txt Plain-Text Output into Title/Description/Value
#'
#' The synthetic doc built by \code{.rd_sections()} always renders \\title
#' first (no header line), followed by \code{Description:} and/or
#' \code{Value:} in that order (whichever sections were present), each
#' starting at column 0 with the section's plain content indented beneath
#' it. \\arguments never reaches here -- see \code{.rd_arguments()}.
#'
#' @param txt Character. Full \code{Rd2txt()} output for the synthetic doc.
#' @return A list with \code{title}, \code{description}, and \code{value}
#'   (character, each possibly \code{NULL}).
#' @noRd
.parse_rd_txt <- function(txt) {
  lines <- strsplit(txt, "\n", fixed = TRUE)[[1L]]
  headers <- c("Description:", "Value:")
  header_idx <- which(trimws(lines) %in% headers & !grepl("^\\s", lines))

  title_end <- if (length(header_idx) > 0L) header_idx[1L] - 1L else length(lines)
  title <- .clean_rd_text(paste(lines[seq_len(max(title_end, 0L))], collapse = " "))
  if (!nzchar(title)) title <- NULL

  segments <- list()
  if (length(header_idx) > 0L) {
    for (j in seq_along(header_idx)) {
      hname <- sub(":$", "", trimws(lines[header_idx[j]]))
      seg_end <- if (j < length(header_idx)) header_idx[j + 1L] - 1L else length(lines)
      seg_start <- header_idx[j] + 1L
      segments[[hname]] <- if (seg_start <= seg_end) lines[seg_start:seg_end] else character(0)
    }
  }

  description <- NULL
  if (!is.null(segments[["Description"]])) {
    description <- .first_paragraph(segments[["Description"]])
    if (nchar(description) > 600L) description <- substr(description, 1L, 600L)
    if (!nzchar(description)) description <- NULL
  }

  value <- NULL
  if (!is.null(segments[["Value"]])) {
    value <- .clean_rd_text(paste(segments[["Value"]], collapse = " "))
    if (nchar(value) > 400L) value <- substr(value, 1L, 400L)
    if (!nzchar(value)) value <- NULL
  }

  list(title = title, description = description, value = value)
}


#' First Paragraph of a Text Block (Lines Up to the First Blank Line)
#'
#' Skips any leading blank line(s) first (Rd2txt always puts one between a
#' section header and its content), then returns everything up to the next
#' blank line -- otherwise that leading blank line would itself look like
#' the end of an (empty) first paragraph.
#'
#' @noRd
.first_paragraph <- function(body_lines) {
  nz <- which(nzchar(trimws(body_lines)))
  if (length(nz) == 0L) {
    return("")
  }
  body_lines <- body_lines[nz[1L]:length(body_lines)]
  blank <- which(!nzchar(trimws(body_lines)))
  first_blank <- if (length(blank) > 0L) blank[1L] - 1L else length(body_lines)
  .clean_rd_text(paste(body_lines[seq_len(max(first_blank, 0L))], collapse = " "))
}


#' Parse an Rd \\arguments Section Structurally
#'
#' Walks the PARSED Rd tree rather than re-parsing rendered text. Inside
#' \\arguments, every parameter is an \\item node with exactly two children:
#' the term (one or more comma-separated parameter names) and the
#' description. Reading those two children directly is exact, so none of
#' the text-shape heuristics the old renderer-based parser needed -- item
#' boundaries inferred from blank lines, continuation paragraphs told apart
#' from new items by indentation, terms split on the first colon -- exist
#' here to be wrong. Two real bugs came out of those heuristics: a
#' multi-paragraph argument description whose continuation happened to
#' contain a colon was parsed as a BOGUS extra parameter, and a parameter
#' whose description contained a colon could lose text ahead of it.
#'
#' Verified across all eight TaxaID packages: 1317 of 1317 \\item nodes have
#' exactly two children, so the two-child assumption is not merely the
#' documented Rd grammar but true of this corpus. An \\item that somehow
#' does not is skipped rather than guessed at.
#'
#' @param args_tag The \\code{\\arguments} node of a parsed Rd object.
#' @return Named list: parameter name -> doc text (character). Parameters
#'   sharing one \\item (\\code{\\item{x, y}{...}}) each get the same text.
#' @noRd
.rd_arguments <- function(args_tag) {
  out <- list()
  if (!is.list(args_tag)) {
    return(out)
  }

  for (node in args_tag) {
    if (!identical(attr(node, "Rd_tag") %||% "", "\\item")) next
    if (!is.list(node) || length(node) != 2L) next

    term <- .rd_text(node[[1L]])
    if (!nzchar(term)) next
    doc_text <- .rd_text(node[[2L]])

    # \item{x, y}{...} documents both x and y with the same text.
    names_here <- trimws(strsplit(term, ",", fixed = TRUE)[[1L]])
    names_here <- names_here[nzchar(names_here)]
    for (nm in names_here) out[[nm]] <- doc_text
  }

  out
}


#' Flatten a Parsed Rd Node to Plain Text
#'
#' Recursively renders an Rd tree fragment to a single plain-text string,
#' keeping the text a reader would see and dropping the markup around it.
#' Leaf nodes (\code{TEXT}, \code{RCODE}, \code{VERB}) are literal; markup
#' macros contribute their children's text; \code{COMMENT} and
#' \code{\\out} (format-specific escape hatches) contribute nothing.
#'
#' Two-argument macros need care: \code{\\eqn{latex}{ascii}} and
#' \code{\\if{format}{text}} must NOT render both children, or the registry
#' would carry LaTeX source or a bare format name as if it were prose.
#'
#' @param node A parsed Rd node, or a list of them.
#' @return A single character string, whitespace-collapsed.
#' @noRd
.rd_text <- function(node) {
  .clean_rd_text(paste(.rd_text_parts(node), collapse = ""))
}


#' Recursive Worker for .rd_text()
#'
#' @param node A parsed Rd node, or a list of them.
#' @return Character vector of text fragments, in document order.
#' @noRd
.rd_text_parts <- function(node) {
  if (is.null(node)) {
    return(character(0))
  }
  tag <- attr(node, "Rd_tag") %||% ""

  # Leaves: the parser stores the literal text as a character vector.
  if (is.character(node)) {
    if (tag %in% c("COMMENT", "\\out")) {
      return(character(0))
    }
    return(as.character(node))
  }
  if (!is.list(node)) {
    return(character(0))
  }

  switch(tag,
    # Drop entirely: not reader-visible text.
    "COMMENT" = return(character(0)),
    "\\out" = return(character(0)),
    # \eqn{latex}{ascii}, \deqn likewise: prefer the ASCII rendering when the
    # author supplied one, never both.
    "\\eqn" = ,
    "\\deqn" = return(.rd_text_parts(node[[length(node)]])),
    # \if{format}{text} / \ifelse: the first child is the FORMAT NAME, not text.
    "\\if" = if (length(node) >= 2L) return(.rd_text_parts(node[[2L]])) else return(character(0)),
    "\\ifelse" = if (length(node) >= 2L) return(.rd_text_parts(node[[2L]])) else return(character(0)),
    # Line/paragraph breaks become a space; \clean_rd_text collapses runs.
    "\\cr" = return(" "),
    NULL
  )

  # \item inside a nested \itemize/\describe: separate the term from its
  # body so the two do not run together into one word.
  if (identical(tag, "\\item") && length(node) == 2L) {
    return(c(" ", .rd_text_parts(node[[1L]]), ": ", .rd_text_parts(node[[2L]])))
  }

  unlist(lapply(node, .rd_text_parts), use.names = FALSE) %||% character(0)
}


#' Clean Rd2txt Plain-Text Output
#'
#' Strips any leftover overstrike bold/underline markup (a character
#' followed by a backspace, produced by \code{Rd2txt()} when
#' \code{underline_titles} is not disabled -- defensive here since
#' \code{.rd_sections()} always passes \code{underline_titles = FALSE}) and
#' collapses all whitespace (including newlines) to single spaces.
#'
#' @param x Character.
#' @return Character, trimmed.
#' @noRd
.clean_rd_text <- function(x) {
  # Overstrike markup is CHAR + backspace pairs; drop the CHAR each time a
  # backspace follows it (repeat once for doubly-overstruck bold-underline).
  x <- gsub("(?s).\x08", "", x, perl = TRUE)
  x <- gsub("(?s).\x08", "", x, perl = TRUE)
  x <- gsub("[ \t]*\n[ \t]*", " ", x)
  x <- gsub("[ \t]+", " ", x)
  trimws(x)
}


#' Compress the Registry for Prompt Injection
#'
#' Converts the full introspected registry into a token-efficient text
#' block suitable for the \code{{{FUNCTION_REGISTRY}}} placeholder in the
#' system prompt: one line per function, showing its real call signature
#' (parameter names and defaults, in \code{formals()} order -- no type
#' column, because the registry no longer carries per-parameter types) and
#' its Rd title.
#'
#' @param registry Named list from \code{workflow_registry()}.
#' @return Character string.
#' @noRd
.compress_registry <- function(registry) {
  lines <- character(0)
  for (pkg_name in names(registry)) {
    pkg <- registry[[pkg_name]]
    lines <- c(lines, sprintf("## %s", pkg_name))
    for (fn in pkg$functions) {
      sig <- .format_registry_signature(fn)
      title <- fn$title %||% ""
      lines <- c(lines, sprintf("- %s::%s(%s) | %s", pkg_name, fn$name, sig, title))
    }
    lines <- c(lines, "")
  }
  paste(lines, collapse = "\n")
}


#' Format One Function's Call Signature for the Compressed Registry
#' @noRd
.format_registry_signature <- function(fn) {
  if (length(fn$params) == 0L) {
    return("")
  }
  parts <- vapply(fn$params, function(p) {
    if (isTRUE(p$required)) {
      p$name
    } else {
      sprintf("%s = %s", p$name, p$default %||% "NULL")
    }
  }, character(1))
  paste(parts, collapse = ", ")
}


#' Produce a Parameter-Documentation Block for a Set of Functions
#'
#' The PARAM_DOCS block injected into the parameterize/error_fix phase
#' prompts: for each requested function name, its package, required/default
#' status per parameter, and the Rd argument text (when available).
#'
#' @param registry Named list from \code{workflow_registry()}.
#' @param functions Character vector of function names to document.
#' @param packages Optional character vector restricting the search to
#'   these packages (matches the old per-edge \code{packages} scoping).
#'   Default \code{NULL} searches every package in \code{registry}.
#' @return Character string.
#' @noRd
.registry_docs <- function(registry, functions, packages = NULL) {
  search_pkgs <- if (is.null(packages)) names(registry) else intersect(packages, names(registry))

  lines <- character(0)
  for (fn_name in functions) {
    doc <- NULL
    doc_pkg <- NULL
    for (pkg in search_pkgs) {
      pkg_entry <- registry[[pkg]]
      if (is.null(pkg_entry)) next
      for (fn_def in pkg_entry$functions) {
        if (identical(fn_def$name, fn_name)) {
          doc <- fn_def
          doc_pkg <- pkg
          break
        }
      }
      if (!is.null(doc)) break
    }

    if (is.null(doc)) {
      lines <- c(lines, sprintf("## %s\n(no registry entry available)\n", fn_name))
      next
    }

    param_lines <- character(0)
    for (p in doc$params) {
      req <- if (isTRUE(p$required)) " (REQUIRED)" else ""
      def <- if (!is.null(p$default)) sprintf(" [default: %s]", p$default) else ""
      desc <- p$doc %||% ""
      param_lines <- c(
        param_lines,
        sprintf("  - %s: %s%s%s", p$name, desc, req, def)
      )
    }

    lines <- c(
      lines,
      sprintf("## %s::%s", doc_pkg %||% "?", fn_name),
      if (length(param_lines) > 0L) param_lines else "  (no params)",
      ""
    )
  }

  paste(lines, collapse = "\n")
}
