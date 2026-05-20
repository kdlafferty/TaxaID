# ==============================================================================
# report_section.R
# TaxaTools -- S3 class for per-package report sections
#
# Exported functions:
#   new_report_section()   -- constructor
#   print.report_section() -- print method (emits markdown)
#   format.report_section() -- format method (returns markdown string)
#   assemble_report()      -- combine multiple report_section objects
#
# Each TaxaID package exports a report_*() function that returns a
# report_section object. These can be used standalone or assembled into
# a unified report via assemble_report().
#
# Session 65: initial implementation
# ==============================================================================


# ==============================================================================
# new_report_section()
# ==============================================================================

#' Create a Report Section Object
#'
#' Constructor for the \code{report_section} S3 class used by per-package
#' report functions throughout the TaxaID ecosystem. Each package's
#' \code{report_*()} function returns a \code{report_section} object that
#' can be printed standalone or assembled into a unified report via
#' \code{\link{assemble_report}}.
#'
#' @param package Character. Package name (e.g. \code{"TaxaFetch"}).
#' @param section Character. Short section identifier (e.g. \code{"fetch"},
#'   \code{"match"}, \code{"likelihood"}).
#' @param methods Character. Methods text (template-based, deterministic).
#' @param results Character. Results text (template or LLM-generated).
#' @param citations Character vector or \code{NULL}. Bibliographic citations
#'   associated with this pipeline step.
#' @param params Named list or \code{NULL}. Key parameters used in this step
#'   (for reproducibility and downstream assembly).
#' @param statistics Named list or \code{NULL}. Summary statistics computed
#'   in this step.
#'
#' @return A \code{report_section} object (S3 list).
#'
#' @examples
#' sec <- new_report_section(
#'   package    = "TaxaFetch",
#'   section    = "fetch",
#'   methods    = "Occurrence records were obtained from GBIF.",
#'   results    = "A total of 1,234 records were compiled.",
#'   citations  = c("GBIF.org. GBIF Occurrence Download via rgbif"),
#'   params     = list(year_range = "2000,2024"),
#'   statistics = list(n_records = 1234L)
#' )
#' print(sec)
#'
#' @export
new_report_section <- function(package,
                               section,
                               methods,
                               results    = NULL,
                               citations  = NULL,
                               params     = NULL,
                               statistics = NULL) {

  if (!is.character(package) || length(package) != 1L || !nzchar(package))
    stop("'package' must be a non-empty single string.", call. = FALSE)
  if (!is.character(section) || length(section) != 1L || !nzchar(section))
    stop("'section' must be a non-empty single string.", call. = FALSE)
  if (!is.character(methods) || length(methods) != 1L)
    stop("'methods' must be a single character string.", call. = FALSE)
  if (!is.null(results) && (!is.character(results) || length(results) != 1L))
    stop("'results' must be a single character string or NULL.", call. = FALSE)
  if (!is.null(citations) && !is.character(citations))
    stop("'citations' must be a character vector or NULL.", call. = FALSE)
  if (!is.null(params) && !is.list(params))
    stop("'params' must be a named list or NULL.", call. = FALSE)
  if (!is.null(statistics) && !is.list(statistics))
    stop("'statistics' must be a named list or NULL.", call. = FALSE)

  structure(
    list(
      package    = package,
      section    = section,
      methods    = methods,
      results    = results,
      citations  = citations,
      params     = params,
      statistics = statistics
    ),
    class = "report_section"
  )
}


# ==============================================================================
# print.report_section()
# ==============================================================================

#' Print a Report Section
#'
#' Displays the methods and results text as markdown.
#'
#' @param x A \code{report_section} object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export
print.report_section <- function(x, ...) {
  cat(sprintf("--- %s (%s) ---\n\n", x$package, x$section))
  cat("## Methods\n\n")
  cat(x$methods, "\n")
  if (!is.null(x$results)) {
    cat("\n## Results\n\n")
    cat(x$results, "\n")
  }
  if (!is.null(x$citations) && length(x$citations) > 0L) {
    cat("\n## Data Sources\n\n")
    for (cit in x$citations) cat(sprintf("- %s\n", cit))
  }
  cat("\n")
  invisible(x)
}


# ==============================================================================
# format.report_section()
# ==============================================================================

#' Format a Report Section as Markdown
#'
#' Returns the full markdown text for this section.
#'
#' @param x A \code{report_section} object.
#' @param ... Ignored.
#' @return Character string with markdown content.
#' @export
format.report_section <- function(x, ...) {
  parts <- character(0L)
  parts <- c(parts, "## Methods\n", x$methods)
  if (!is.null(x$results)) {
    parts <- c(parts, "\n## Results\n", x$results)
  }
  if (!is.null(x$citations) && length(x$citations) > 0L) {
    parts <- c(parts, "\n## Data Sources\n",
               paste(sprintf("- %s", x$citations), collapse = "\n"))
  }
  paste(parts, collapse = "\n")
}


# ==============================================================================
# assemble_report()
# ==============================================================================

#' Assemble Multiple Report Sections into a Unified Report
#'
#' Takes any number of \code{report_section} objects (typically one per
#' TaxaID package used in a pipeline) and assembles them into a single
#' markdown document. Sections are ordered by their position in the
#' standard TaxaID pipeline. Citations are deduplicated and collected
#' into a single "Data Sources" section at the end.
#'
#' @param ... \code{report_section} objects, in any order.
#' @param title Character or \code{NULL}. Optional report title.
#' @param study_description Character or \code{NULL}. Optional study
#'   description paragraph inserted before the Methods sections.
#'
#' @return Character string containing the full assembled markdown report.
#'
#' @examples
#' \dontrun{
#' fetch_sec  <- report_fetch(occurrences)
#' match_sec  <- report_match(match_data)
#' assign_sec <- report_assign(result, consensus)
#' full_report <- assemble_report(fetch_sec, match_sec, assign_sec,
#'                                title = "eDNA Taxonomic Assignment Report")
#' cat(full_report)
#' }
#'
#' @export
assemble_report <- function(...,
                            title = NULL,
                            study_description = NULL) {

  sections <- list(...)

  # Validate inputs

  if (length(sections) == 0L)
    stop("assemble_report: at least one report_section object required.",
         call. = FALSE)

  # Accept a single list of sections (convenience)
  if (length(sections) == 1L && is.list(sections[[1L]]) &&
      !inherits(sections[[1L]], "report_section")) {
    sections <- sections[[1L]]
  }

  not_section <- !vapply(sections, inherits, logical(1L), "report_section")
  if (any(not_section))
    stop("assemble_report: all arguments must be report_section objects.",
         call. = FALSE)

  # Order by pipeline position
  pipeline_order <- c("fetch", "match", "likelihood", "habitat",
                      "priors", "assign", "flags")
  section_ids <- vapply(sections, function(s) s$section, character(1L))
  order_idx   <- match(section_ids, pipeline_order)
  # Unknown sections go at the end
  order_idx[is.na(order_idx)] <- length(pipeline_order) + 1L
  sections <- sections[order(order_idx)]

  # Build output
  output <- character(0L)

  if (!is.null(title)) {
    output <- c(output, sprintf("# %s\n", title))
  }

  if (!is.null(study_description)) {
    output <- c(output, study_description, "")
  }

  # Methods
  output <- c(output, "## Methods\n")
  for (sec in sections) {
    output <- c(output, sprintf("### %s\n", .section_heading(sec$section)))
    output <- c(output, sec$methods, "")
  }

  # Results
  has_results <- vapply(sections, function(s) !is.null(s$results), logical(1L))
  if (any(has_results)) {
    output <- c(output, "## Results\n")
    for (sec in sections[has_results]) {
      output <- c(output, sprintf("### %s\n", .section_heading(sec$section)))
      output <- c(output, sec$results, "")
    }
  }

  # Citations (deduplicated across all sections)
  all_citations <- unique(unlist(lapply(sections, function(s) s$citations)))
  if (length(all_citations) > 0L) {
    output <- c(output, "## Data Sources\n")
    output <- c(output, paste(sprintf("- %s", all_citations), collapse = "\n"))
    output <- c(output, "")
  }

  paste(output, collapse = "\n")
}


# ==============================================================================
# Internal: section heading lookup
# ==============================================================================

#' @noRd
.section_heading <- function(section) {
  headings <- c(
    fetch      = "Data Acquisition",
    match      = "Sequence Matching",
    likelihood = "Likelihood Estimation",
    habitat    = "Habitat Assignment",
    priors     = "Prior Estimation",
    assign     = "Taxonomic Assignment",
    flags      = "Quality Flagging"
  )
  if (section %in% names(headings)) headings[[section]] else section
}
