# ==============================================================================
# pdf_text.R
# TaxaFetch — PDF section detection and text extraction
#
# Provides the foundation for the PDF occurrence pipeline. Uses pdftools
# for lightweight text extraction and section detection; page images for
# the API are handled in pdf_api.R.
#
# Exported functions:
#   extract_pdf_text()        Extract text by section from a PDF file
#
# Internal helpers (@noRd):
#   .section_patterns         Named list of canonical section header patterns
#   .skip_sections            Character vector of sections excluded by default
#   .extract_sections         Character vector of sections included by default
#   .detect_pdf_sections()    Scan page text for section headers; return page map
#   .match_header()           Test whether a line of text is a section header
#
# Relationship to DataONE pipeline:
#   Analogous to the EML parsing step inside fetch_dataone_eml() and
#   screen_eml_columns(), which read document structure to identify what
#   content is present before committing to a full download. Here we read
#   PDF structure to identify which pages contain which sections before
#   committing to API image calls.
#
# Dependencies:
#   pdftools (Suggests) — pdf_text(), pdf_info()
#
# Token management strategy:
#   Stage 1 screen  — abstract text only (no API image call)
#   Stage 2 characterize — abstract + methods + results as text
#   Stage 3 extract — methods + results + appendix as page images
#   This file handles stages 1 and 2. pdf_api.R handles stage 3.
# ==============================================================================


# ==============================================================================
# Section vocabulary
# ==============================================================================

#' Canonical section header patterns
#'
#' Named list mapping section labels to character vectors of patterns.
#' Patterns are matched case-insensitively against short lines of PDF text.
#' Stored as a package-internal object; users should not modify this directly
#' but can pass a custom list to extract_pdf_text().
#'
#' @noRd
.section_patterns <- list(
  abstract         = c("abstract"),
  introduction     = c("introduction"),
  methods          = c("methods", "materials and methods",
                       "materials & methods",
                       "study site", "study area", "study system",
                       "study region", "field methods",
                       "sampling methods", "data collection"),
  results          = c("results", "results and discussion"),
  discussion       = c("discussion"),
  acknowledgements = c("acknowledgements", "acknowledgments",
                       "acknowledgement", "acknowledgment"),
  funding          = c("funding", "financial support",
                       "funding information", "grant information"),
  references       = c("references", "literature cited",
                       "bibliography", "works cited",
                       "references cited"),
  appendix         = c("appendix", "supplementary material",
                       "supplementary materials",
                       "supplementary information",
                       "supporting information",
                       "online supplementary", "data accessibility",
                       "data availability"),
  figures          = c("figure captions", "list of figures",
                       "figure legends")
)

#' Sections excluded from extraction by default
#'
#' These sections are skipped in Stage 2 (characterize) and Stage 3 (extract)
#' because they contain no primary occurrence data. Discussion is excluded
#' because species mentions there are comparative, not observational.
#'
#' @noRd
.skip_sections <- c("discussion", "acknowledgements",
                    "funding", "references", "figures")

#' Sections included in extraction by default
#'
#' @noRd
.extract_sections <- c("abstract", "introduction", "methods",
                       "results", "appendix")


# ==============================================================================
# Internal: .match_header()
# ==============================================================================

#' Test whether a text line is a section header
#'
#' A line is considered a section header candidate if it is short (under
#' max_chars characters), non-empty, and matches one of the patterns in
#' the provided vocabulary after stripping leading section numbers and
#' trailing punctuation.
#'
#' @param line Character string. A single line of PDF text.
#' @param patterns Named list of character vectors (from .section_patterns).
#' @param max_chars Integer. Maximum line length to consider as a header.
#'   Default 80L. Longer lines are almost certainly prose, not headers.
#'
#' @return Character string: the matched section label (e.g. "methods"),
#'   or NA_character_ if no match.
#' @noRd
.match_header <- function(line, patterns, max_chars = 80L) {

  line <- trimws(line)
  if (!nzchar(line)) return(NA_character_)

  # ---- Pass 1: standard match (short lines only) ------------------------------
  # Handles single-column layouts where headers appear alone on a line.
  if (nchar(line) <= max_chars) {

    # Strip leading section numbers: "2.", "2.1", "II.", "II.1" etc.
    clean <- gsub("^[0-9IVXivx]+\\.?[0-9]*\\.?\\s*", "", line)
    # Strip trailing punctuation
    clean <- gsub("[[:punct:]]+$", "", clean)
    clean <- trimws(clean)

    if (nzchar(clean)) {
      clean_lower <- tolower(clean)
      for (label in names(patterns)) {
        for (pat in patterns[[label]]) {
          if (clean_lower == tolower(pat)) return(label)
        }
      }
    }
  }

  # ---- Pass 2: all-caps header embedded in longer line -----------------------
  # Two-column PDF layouts (common in journals) cause pdftools to interleave
  # left and right column text on the same line. A section header in the left
  # column (e.g. "METHODS") appears mid-line next to right-column prose,
  # making the combined line too long for Pass 1. This pass extracts any
  # all-caps token (<= 40 chars, no digits) at the START of the line and
  # tests it against the vocabulary. This reliably catches INTRODUCTION,
  # METHODS, RESULTS, DISCUSSION without false-matching abbreviations or
  # accession numbers embedded mid-line.
  leading_caps <- regmatches(line,
                             regexpr("^[A-Z][A-Z &]{2,39}(?=\\s)",
                                     line, perl = TRUE))
  if (length(leading_caps) == 1L && nzchar(leading_caps)) {
    caps_lower <- tolower(trimws(leading_caps))
    for (label in names(patterns)) {
      for (pat in patterns[[label]]) {
        if (caps_lower == tolower(pat)) return(label)
      }
    }
  }

  NA_character_
}


# ==============================================================================
# Internal: .detect_pdf_sections()
# ==============================================================================

#' Detect section boundaries in PDF page text
#'
#' Scans a character vector of page texts (one element per page, as returned
#' by pdftools::pdf_text()) for section headers, and returns a named list
#' mapping section labels to the page range they occupy.
#'
#' When no section headers are detected (e.g. short reports with no explicit
#' headings), returns a single entry "document" covering all pages, and sets
#' has_headers = FALSE in the result attributes.
#'
#' @param pages_text Character vector. One element per page, as from
#'   pdftools::pdf_text().
#' @param patterns Named list of section header patterns. Defaults to
#'   .section_patterns.
#' @param max_header_chars Integer. Max line length for header candidate.
#'   Default 80L.
#'
#' @return Named list where each element is an integer vector of page numbers
#'   (1-based) belonging to that section. Attribute \code{has_headers} is
#'   TRUE if at least one header was detected, FALSE otherwise.
#'
#' @noRd
.detect_pdf_sections <- function(pages_text,
                                 patterns         = .section_patterns,
                                 max_header_chars = 80L) {

  n_pages <- length(pages_text)

  # ---- scan every line of every page for header matches ----------------------
  # page_labels: one entry per page, the section label detected on that page
  # (NA if no header found on that page, or the label of the LAST header found
  # if multiple headers appear on one page — e.g. very short sections)

  page_section <- rep(NA_character_, n_pages)

  for (pg in seq_len(n_pages)) {
    lines <- strsplit(pages_text[pg], "\n")[[1L]]
    for (ln in lines) {
      hit <- .match_header(ln, patterns, max_chars = max_header_chars)
      if (!is.na(hit)) {
        page_section[pg] <- hit
        # Don't break — a page can introduce a new section part-way through,
        # and the last header on the page wins (forward-fill logic below will
        # propagate it).
      }
    }
  }

  # ---- forward-fill section labels ------------------------------------------
  # Pages without a header belong to the preceding section.
  filled <- page_section
  current <- NA_character_
  for (pg in seq_len(n_pages)) {
    if (!is.na(filled[pg])) {
      current <- filled[pg]
    } else {
      filled[pg] <- current
    }
  }

  # Pages before the first detected header (filled[pg] still NA) are treated
  # as abstract/preamble.
  filled[is.na(filled)] <- "abstract"

  has_headers <- any(!is.na(page_section))

  # ---- build section -> page list -------------------------------------------
  if (!has_headers) {
    result <- list(document = seq_len(n_pages))
    attr(result, "has_headers") <- FALSE
    return(result)
  }

  section_labels <- unique(filled)
  result <- lapply(section_labels, function(s) which(filled == s))
  names(result) <- section_labels
  attr(result, "has_headers") <- TRUE

  result
}


# ==============================================================================
# Internal: .detect_document_boundary()
# ==============================================================================

#' Detect the last page belonging to the target article
#'
#' Many PDFs retrieved from journal archives contain additional articles or
#' back matter (volume indices, conference announcements, etc.) after the
#' target paper ends. This helper identifies the boundary page — the first
#' page that belongs to a different article — and returns the index of the
#' last page that should be kept.
#'
#' Two complementary triggers are tested in order:
#'
#' \strong{Trigger 1 — Journal citation header repeat:} A journal article
#' typically begins with a short header line matching the pattern
#' \code{volume(issue), year, pp. X-Y}. If this pattern appears on page 1
#' and then reappears on a later page with a different page range, that page
#' starts a new article.
#'
#' \strong{Trigger 2 — Banner line repeat:} The first three non-empty short
#' lines on page 1 (likely the journal name and volume line) are collected.
#' If any of them reappear verbatim on a later page, that page starts a new
#' article. This catches cases where Trigger 1 does not match (e.g. older
#' volume/issue formatting).
#'
#' If neither trigger fires, all pages are returned unchanged.
#'
#' @param pages_text Character vector. One element per page, as from
#'   \code{pdftools::pdf_text()}.
#' @param min_boundary Integer. Minimum page index to consider as a boundary.
#'   Default \code{10L} — prevents false positives on the first few pages
#'   where running headers may repeat journal metadata.
#'
#' @return Integer. Index of the last page to keep (1-based). Returns
#'   \code{length(pages_text)} if no boundary is detected.
#'
#' @noRd
.detect_document_boundary <- function(pages_text, min_boundary = 10L) {

  n <- length(pages_text)
  if (n <= min_boundary) return(n)

  p1_lines <- trimws(strsplit(pages_text[[1L]], "\n")[[1L]])
  p1_lines <- p1_lines[nzchar(p1_lines)]

  # ------------------------------------------------------------------
  # Trigger 1 — journal citation header: "vol(issue), year, pp. X-Y"
  # Matches patterns like: "92(3), 1993, pp. 101-167"
  # or: "Vol. 92, No. 3, 1993, pp. 101-167"
  # ------------------------------------------------------------------
  cite_pat <- "[0-9]+\\([0-9]+\\),\\s*[0-9]{4}|[Vv]ol\\.?\\s*[0-9]"
  page_range_pat <- "pp\\.\\s*[0-9]+-[0-9]+"

  p1_cite_lines <- p1_lines[
    grepl(cite_pat, p1_lines) & grepl(page_range_pat, p1_lines)
  ]

  if (length(p1_cite_lines) > 0L) {
    # Extract the page range from page 1 citation line
    p1_range <- regmatches(
      p1_cite_lines[1L],
      regexpr(page_range_pat, p1_cite_lines[1L])
    )
    for (pg in seq(min_boundary + 1L, n)) {
      pg_lines <- trimws(strsplit(pages_text[[pg]], "\n")[[1L]])
      pg_lines <- pg_lines[nzchar(pg_lines)]
      # Look for a citation-header line with a DIFFERENT page range
      for (ln in pg_lines[grepl(cite_pat, pg_lines) &
                          grepl(page_range_pat, pg_lines)]) {
        pg_range <- regmatches(ln, regexpr(page_range_pat, ln))
        if (length(pg_range) > 0L && pg_range != p1_range) {
          return(pg - 1L)
        }
      }
    }
  }

  # ------------------------------------------------------------------
  # Trigger 2 — banner line repeat
  # Collect the first 3 non-empty short lines from page 1 as candidates.
  # Short = under 90 chars (journal name / volume line, not prose).
  # ------------------------------------------------------------------
  banner_candidates <- p1_lines[nchar(p1_lines) > 5L & nchar(p1_lines) < 90L]
  banner_candidates <- head(banner_candidates, 3L)

  if (length(banner_candidates) > 0L) {
    for (pg in seq(min_boundary + 1L, n)) {
      pg_text <- pages_text[[pg]]
      if (any(vapply(banner_candidates,
                     function(b) grepl(b, pg_text, fixed = TRUE),
                     logical(1L)))) {
        return(pg - 1L)
      }
    }
  }

  # No boundary detected — return all pages
  n
}


# ==============================================================================
# extract_pdf_text()
# ==============================================================================

#' Extract Text by Section from a PDF File
#'
#' Uses \pkg{pdftools} to extract plain text from a PDF, detects section
#' boundaries using header matching, and returns the text of the requested
#' sections as a named list. This is the lightweight first pass used in
#' Stages 1 (screening) and 2 (characterization) of the PDF occurrence
#' pipeline, before committing to more expensive API image calls.
#'
#' @param pdf_path Character string. Path to a PDF file.
#' @param sections Character vector. Section labels to extract. Default
#'   \code{.extract_sections}: abstract, introduction, methods, results,
#'   appendix. Pass \code{"all"} to return all detected sections including
#'   discussion and references.
#' @param patterns Named list. Section header vocabulary. Default
#'   \code{.section_patterns}. Supply a custom list to handle non-standard
#'   section names (e.g. papers that use "Survey Methods" instead of
#'   "Methods").
#' @param max_header_chars Integer. Maximum line length to consider as a
#'   section header. Default \code{80L}.
#' @param truncate_at_boundary Logical. If \code{TRUE} (default), detect and
#'   remove back matter belonging to other articles in the same PDF (e.g.
#'   journal volume indices, symposium announcements) before section detection
#'   runs. Uses journal citation header repeat and banner line repeat as
#'   triggers. Set to \code{FALSE} only if the document genuinely spans
#'   multiple articles that should all be extracted.
#' @param verbose Logical. Report detected sections and page counts. Default
#'   \code{TRUE}.
#'
#' @return A named list with elements:
#'   \describe{
#'     \item{sections}{Named list of character strings, one per requested
#'       section. Each string is the concatenated text of all pages in that
#'       section. Sections not detected in the document are absent.}
#'     \item{page_map}{Named list mapping section labels to integer vectors
#'       of page numbers (1-based).}
#'     \item{has_headers}{Logical. TRUE if section headers were detected.
#'       FALSE means the document has no explicit section structure and
#'       all pages were returned under "document".}
#'     \item{n_pages}{Integer. Total pages in the document.}
#'     \item{pdf_path}{The input path, for passing to downstream functions
#'       without re-specifying.}
#'   }
#'
#' @details
#' \strong{Token management:} This function performs no API calls. It is
#' designed to be called once per PDF; its output is passed to
#' \code{screen_pdf_structure()}
#' (Stage 2), and \code{call_api_pdf()} (Stage 3) so the PDF is
#' parsed only once.
#'
#' \strong{No headers fallback:} If no section headers are detected the
#' entire document is returned under the key \code{"document"} and
#' \code{has_headers} is FALSE. Downstream functions handle this gracefully
#' by treating the full text as equivalent to the abstract + methods +
#' results sections combined.
#'
#' \strong{Relationship to DataONE pipeline:} Analogous to
#' \code{fetch_dataone_eml()}, which reads EML document structure to
#' identify what content is present before committing to a full download.
#' Here we read PDF structure to identify which pages contain which
#' sections before committing to API image calls in Stage 3.
#'
#' \strong{Dependencies:} Requires the \pkg{pdftools} package
#' (\code{install.packages("pdftools")}). The package is listed in
#' Suggests, not Imports, because it is only needed for the PDF pipeline.
#'
#' @seealso \code{\link{screen_pdf_structure}},
#'   \code{\link{call_api_pdf}},
#'   \code{\link{build_pdf_extract_prompt}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' pdf_content <- extract_pdf_text("Swift_et_al_1993.pdf")
#'
#' # What sections were detected?
#' names(pdf_content$sections)
#' pdf_content$has_headers
#'
#' # Inspect the abstract text
#' cat(pdf_content$sections$abstract)
#'
#' # Get only abstract for screening (cheapest path)
#' pdf_content <- extract_pdf_text(
#'   "Swift_et_al_1993.pdf",
#'   sections = "abstract"
#' )
#'
#' # Use custom section vocabulary for a non-standard paper
#' custom_patterns <- .section_patterns
#' custom_patterns$methods <- c(custom_patterns$methods, "survey protocol")
#' pdf_content <- extract_pdf_text("my_paper.pdf", patterns = custom_patterns)
#' }

extract_pdf_text <- function(pdf_path,
                             sections              = .extract_sections,
                             patterns              = .section_patterns,
                             max_header_chars      = 80L,
                             truncate_at_boundary  = TRUE,
                             verbose               = TRUE) {

  # ---- input checks ----------------------------------------------------------
  if (!is.character(pdf_path) || length(pdf_path) != 1L ||
      is.na(pdf_path) || !nzchar(trimws(pdf_path))) {
    stop("extract_pdf_text: 'pdf_path' must be a non-empty character string.")
  }
  if (!file.exists(pdf_path)) {
    stop(sprintf("extract_pdf_text: file not found: %s", pdf_path))
  }
  if (!grepl("\\.pdf$", pdf_path, ignore.case = TRUE)) {
    warning("extract_pdf_text: 'pdf_path' does not have a .pdf extension -- proceeding anyway.",
            call. = FALSE)
  }
  if (!is.character(sections) || length(sections) == 0L) {
    stop("extract_pdf_text: 'sections' must be a non-empty character vector, or \"all\".")
  }
  if (!is.list(patterns) || is.null(names(patterns))) {
    stop("extract_pdf_text: 'patterns' must be a named list.")
  }
  max_header_chars <- as.integer(max_header_chars)
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("extract_pdf_text: 'verbose' must be TRUE or FALSE.")
  }
  if (!is.logical(truncate_at_boundary) || length(truncate_at_boundary) != 1L ||
      is.na(truncate_at_boundary)) {
    stop("extract_pdf_text: 'truncate_at_boundary' must be TRUE or FALSE.")
  }

  # ---- check pdftools available ----------------------------------------------
  if (!requireNamespace("pdftools", quietly = TRUE)) {
    stop(
      "extract_pdf_text: the 'pdftools' package is required for PDF text extraction.\n",
      "Install it with: install.packages(\"pdftools\")"
    )
  }

  # ---- extract page text -----------------------------------------------------
  pages_text <- tryCatch(
    pdftools::pdf_text(pdf_path),
    error = function(e) {
      stop(sprintf(
        "extract_pdf_text: pdftools could not read '%s'.\n  Error: %s",
        pdf_path, conditionMessage(e)
      ))
    }
  )

  n_pages <- length(pages_text)

  if (verbose) {
    message(sprintf("extract_pdf_text: %d pages read from '%s'",
                    n_pages, basename(pdf_path)))
  }

  # ---- document boundary detection ------------------------------------------
  # Truncate pages_text to remove back matter from other articles in the same
  # PDF (journal indices, symposium announcements, etc.) before section
  # detection runs. Uses .detect_document_boundary() which tests for journal
  # citation header repeats and banner line repeats.
  if (truncate_at_boundary && n_pages > 1L) {
    boundary <- .detect_document_boundary(pages_text)
    if (boundary < n_pages) {
      if (verbose) {
        message(sprintf(
          "extract_pdf_text: document boundary detected at page %d -- truncating from %d to %d pages.",
          boundary + 1L, n_pages, boundary
        ))
      }
      pages_text <- pages_text[seq_len(boundary)]
      n_pages    <- boundary
    }
  }

  # ---- detect section boundaries ---------------------------------------------
  page_map   <- .detect_pdf_sections(pages_text, patterns, max_header_chars)
  has_headers <- attr(page_map, "has_headers")

  if (verbose) {
    if (has_headers) {
      message(sprintf(
        "extract_pdf_text: sections detected: %s",
        paste(names(page_map), collapse = ", ")
      ))
    } else {
      message("extract_pdf_text: no section headers detected -- returning full document text.")
    }
  }

  # ---- select requested sections ---------------------------------------------
  if (identical(sections, "all")) {
    requested <- names(page_map)
  } else {
    requested <- intersect(sections, names(page_map))
    missing_secs <- setdiff(sections, names(page_map))
    if (verbose && length(missing_secs) > 0L) {
      message(sprintf(
        "extract_pdf_text: requested sections not detected in document: %s",
        paste(missing_secs, collapse = ", ")
      ))
    }
  }

  # ---- concatenate page text per section ------------------------------------
  section_texts <- lapply(requested, function(s) {
    pg_nums <- page_map[[s]]
    paste(pages_text[pg_nums], collapse = "\n")
  })
  names(section_texts) <- requested

  # ---- return ----------------------------------------------------------------
  list(
    sections    = section_texts,
    page_map    = page_map,
    has_headers = has_headers,
    n_pages     = n_pages,
    pdf_path    = pdf_path
  )
}
