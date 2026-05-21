# ==============================================================================
# pdf_characterize.R
# TaxaFetch -- Stage 2 PDF characterization
#
# Exported functions:
#   screen_pdf_structure()      Classify a PDF on five axes; build page table
#   print.pdf_structure         S3 print method for pdf_structure objects
#
# Internal helpers (@noRd):
#   .build_characterize_prompt()   Build the LLM characterization prompt string
#   .parse_structure_response()    Parse LLM JSON response to axis list
#   .build_page_table()            Build page-level send_image table from text layer
#   .extract_legend_text()         Extract Table/Figure legend sentences from page text
#   .score_legend_for_occurrence() Score a legend string for occurrence relevance
#   .build_abbreviation_inventory() Scan text for Latin binomial abbreviations
#
# Position in the PDF pipeline:
#   Stage 1 -- abstract screen  (build_pdf_screen_prompt / parse_pdf_screen_response)
#   Stage 2 -- THIS FILE        (screen_pdf_structure)
#   Stage 3 -- extraction       (build_pdf_extract_prompt / call_anthropic_api_pdf)
#
# Token management:
#   This function makes ONE cheap text-only LLM call using the already-extracted
#   section texts from extract_pdf_text(). No PDF page images are sent here.
#   The page table (send_image flags) is built from the text layer alone using
#   regex legend screening -- no second API call.
#
# LLM provider note:
#   The llm_fn parameter defaults to call_anthropic_api() but accepts any
#   function with the same signature (one character string in, one character
#   string out). To use a different provider, write a compatible wrapper and
#   pass it as llm_fn. See prompt_api() documentation for an
#   OpenAI-compatible example.
#
#   FUTURE TASK: Add call_openai_api(), call_ollama_api() etc. to
#   llm_api_utils.R so users have first-class alternatives without needing
#   to write their own wrappers. All LLM-calling functions in TaxaFetch
#   should follow this llm_fn pattern -- see AI_CONTEXT.md.
#
# Dependencies:
#   call_anthropic_api() from llm_api_utils.R (TaxaFetch Imports)
#   No additional packages beyond base R and existing TaxaFetch dependencies.
# ==============================================================================


# ==============================================================================
# Vocabulary for legend relevance scoring
# ==============================================================================

# Keywords that suggest a table or figure contains occurrence / locality data.
# Matched case-insensitively against extracted legend text.
.occurrence_legend_keywords <- c(
  "occurrence", "occurrences",
  "record", "records",
  "collect", "collected", "collection",
  "specimen", "specimens",
  "locality", "localities", "location", "locations",
  "station", "stations", "site", "sites",
  "survey", "surveys", "surveyed",
  "trap", "traps", "transect", "transects",
  "sample", "samples", "sampled",
  "observation", "observations",
  "species", "taxa", "taxon",
  "distribution", "range",
  "museum", "voucher",
  "latitude", "longitude", "coordinates",
  "presence", "absence",
  "captured", "detected", "observed", "found",
  "reported", "known from"
)

# Keywords that suggest a table or figure does NOT contain occurrence data.
# A legend matching these without matching occurrence keywords is likely
# statistical, methodological, or conceptual.
.non_occurrence_legend_keywords <- c(
  "anova", "regression", "coefficient",
  "p-value", "p value", "significance",
  "mean", "variance", "standard deviation", "standard error",
  "correlation", "residual",
  "phylogen", "cladogram", "tree",
  "diagram", "schematic", "conceptual",
  "equipment", "apparatus",
  "flow chart", "flowchart",
  "map of.*study area",    # map of study area alone (no species)
  "photograph", "photo"
)


# ==============================================================================
# Internal: .extract_legend_text()
# ==============================================================================

#' Extract Table and Figure legend sentences from a page of PDF text
#'
#' Scans a single page text string for lines beginning with "Table N." or
#' "Fig(ure)? N." and returns the legend text for each match. The legend
#' is taken as the matched line plus any immediately following lines that
#' do not start a new Table/Figure entry and are under max_chars in length
#' (continuation lines).
#'
#' @param page_text Character string. Raw text of one PDF page.
#' @param max_chars Integer. Maximum line length for a continuation line.
#'   Default 300L.
#'
#' @return Named character vector. Names are "Table N" or "Figure N";
#'   values are the full legend text. Empty vector if no legends found.
#' @noRd
.extract_legend_text <- function(page_text, max_chars = 300L) {

  lines  <- strsplit(page_text, "\n")[[1L]]
  lines  <- trimws(lines)
  result <- character(0)
  names_out <- character(0)

  # Pattern: "Table 1.", "Table I.", "Fig. 3.", "Figure 3a.", etc.
  tbl_pat <- "^(Table|Tbl\\.?)\\s+([0-9IVXivx]+[a-zA-Z]?\\.?)"
  fig_pat <- "^(Fig(ure)?\\.?)\\s+([0-9IVXivx]+[a-zA-Z]?\\.?)"

  i <- 1L
  while (i <= length(lines)) {
    ln <- lines[i]
    is_tbl <- grepl(tbl_pat, ln, perl = TRUE)
    is_fig <- grepl(fig_pat, ln, perl = TRUE)

    if (is_tbl || is_fig) {
      # Extract label for naming
      if (is_tbl) {
        label <- regmatches(ln, regexpr(tbl_pat, ln, perl = TRUE))
        label <- sub("\\.$", "", trimws(label))
      } else {
        label <- regmatches(ln, regexpr(fig_pat, ln, perl = TRUE))
        label <- sub("\\.$", "", trimws(label))
        label <- sub("^Fig\\.?\\s+", "Figure ", label)
      }

      # Collect continuation lines
      legend_lines <- ln
      j <- i + 1L
      while (j <= length(lines)) {
        next_ln <- lines[j]
        # Stop if blank, or next table/figure starts, or line is very long
        # (very long lines are body text, not legend continuation)
        if (!nzchar(next_ln)) break
        if (grepl(tbl_pat, next_ln, perl = TRUE)) break
        if (grepl(fig_pat, next_ln, perl = TRUE)) break
        if (nchar(next_ln) > max_chars) break
        legend_lines <- c(legend_lines, next_ln)
        j <- j + 1L
      }
      result    <- c(result, paste(legend_lines, collapse = " "))
      names_out <- c(names_out, label)
      i <- j
    } else {
      i <- i + 1L
    }
  }

  if (length(result) == 0L) return(character(0))
  stats::setNames(result, names_out)
}


# ==============================================================================
# Internal: .score_legend_for_occurrence()
# ==============================================================================

#' Score a legend string for occurrence data relevance
#'
#' Returns TRUE if the legend text contains occurrence keywords and does not
#' appear to be purely statistical/conceptual. Ambiguous legends (no strong
#' signal either way) return TRUE (send image -- conservative default).
#'
#' @param legend_text Character string. Full legend text for one table or figure.
#'
#' @return Logical. TRUE = send image to API; FALSE = skip.
#' @noRd
.score_legend_for_occurrence <- function(legend_text) {

  if (!nzchar(trimws(legend_text))) return(FALSE)

  txt_lower <- tolower(legend_text)

  n_occ     <- sum(vapply(.occurrence_legend_keywords,
                          function(k) grepl(k, txt_lower, fixed = TRUE),
                          logical(1L)))
  n_non_occ <- sum(vapply(.non_occurrence_legend_keywords,
                          function(k) grepl(k, txt_lower, perl = TRUE),
                          logical(1L)))

  # Strong non-occurrence signal with no occurrence signal -> skip
  if (n_non_occ >= 2L && n_occ == 0L) return(FALSE)
  # Any occurrence signal -> send
  if (n_occ >= 1L) return(TRUE)
  # No signal either way -> conservative: send (ambiguous legends processed by model)
  TRUE
}


# ==============================================================================
# Internal: .build_page_table()
# ==============================================================================

#' Build the page-level classification table
#'
#' For each page in the document, determines:
#'   - section label (from page_map)
#'   - content_type: "prose", "table", "figure", "mixed", or "references"
#'   - legend_text: extracted legend string(s), NA if none
#'   - send_image: TRUE if this page should be sent as an image in Stage 3
#'
#' Pages in skip sections (discussion, acknowledgements, funding, references)
#' are flagged send_image = FALSE regardless of content.
#' Pages beyond the document boundary (post-references back matter) are
#' also flagged FALSE.
#'
#' @param pages_text Character vector. One element per page (pdftools::pdf_text output).
#' @param page_map Named list mapping section labels to integer page vectors.
#' @param has_supplementary Logical. If TRUE, appendix pages are always included.
#'
#' @return Data frame with columns: page (integer), section (character),
#'   content_type (character), legend_text (character, NA if absent),
#'   send_image (logical).
#' @noRd
.build_page_table <- function(pages_text, page_map, has_supplementary = FALSE) {

  n_pages <- length(pages_text)

  # Build page -> section lookup from page_map
  page_section <- rep(NA_character_, n_pages)
  for (sec in names(page_map)) {
    page_section[page_map[[sec]]] <- sec
  }
  # Pages with no section label are treated as "unknown"
  page_section[is.na(page_section)] <- "unknown"

  # Sections that are never sent to the extraction API
  skip_secs <- c("discussion", "acknowledgements", "funding",
                 "references", "figures", "unknown")
  # Sections that are always sent
  keep_secs <- c("abstract", "introduction", "methods", "results")
  # Appendix: sent only if has_supplementary = TRUE or appendix is present
  appendix_secs <- c("appendix")

  rows <- vector("list", n_pages)

  for (pg in seq_len(n_pages)) {
    pg_text <- pages_text[pg]
    sec     <- page_section[pg]

    # Extract legends for this page
    legends     <- .extract_legend_text(pg_text)
    legend_text <- if (length(legends) == 0L) NA_character_
                   else paste(legends, collapse = " | ")

    # Classify content type from text-layer signals
    has_table  <- length(legends) > 0L &&
                  any(grepl("^Table", names(legends)))
    has_figure <- length(legends) > 0L &&
                  any(grepl("^Figure", names(legends)))
    has_prose  <- nchar(trimws(pg_text)) > 200L

    content_type <- if (has_table && has_figure) "mixed"
                    else if (has_table)           "table"
                    else if (has_figure)          "figure"
                    else if (has_prose)           "prose"
                    else                          "other"

    # Determine send_image flag
    if (sec %in% skip_secs) {
      send_image <- FALSE

    } else if (sec %in% keep_secs) {
      # Always send prose and table pages in core sections
      # Figure pages: only send if legend scores as occurrence-relevant
      if (content_type == "figure") {
        send_image <- if (length(legends) > 0L) {
          any(vapply(legends, .score_legend_for_occurrence, logical(1L)))
        } else {
          FALSE   # figure page with no detectable legend -> skip
        }
      } else {
        send_image <- TRUE
      }

    } else if (sec %in% appendix_secs) {
      # Appendix pages: send only if has_supplementary flagged
      # and legend (if present) scores as occurrence-relevant
      if (!has_supplementary) {
        send_image <- FALSE
      } else if (content_type == "figure") {
        send_image <- if (length(legends) > 0L) {
          any(vapply(legends, .score_legend_for_occurrence, logical(1L)))
        } else {
          FALSE
        }
      } else {
        send_image <- TRUE
      }

    } else {
      # "document" fallback (no headers detected) -- send everything
      send_image <- TRUE
    }

    rows[[pg]] <- data.frame(
      page         = pg,
      section      = sec,
      content_type = content_type,
      legend_text  = legend_text,
      send_image   = send_image,
      stringsAsFactors = FALSE
    )
  }

  do.call(rbind, rows)
}


# ==============================================================================
# Internal: .build_abbreviation_inventory()
# ==============================================================================

#' Build an inventory of Latin binomial abbreviations from document text
#'
#' Scans the combined section text for the pattern of a full binomial on first
#' mention (e.g. "Eucyclogobius newberryi") followed by abbreviated use
#' (e.g. "E. newberryi") on subsequent mentions. Returns a named character
#' vector mapping abbreviation -> full binomial.
#'
#' This is used by the extraction prompt to tell the model how to expand
#' abbreviated names back to full binomials before outputting records.
#'
#' @param text Character string. Concatenated text of relevant sections.
#'
#' @return Named character vector. Names are abbreviations (e.g. "E. newberryi");
#'   values are full binomials (e.g. "Eucyclogobius newberryi"). Empty named
#'   vector if none detected. Duplicate abbreviation keys are removed, keeping
#'   the first full binomial encountered. Spelling variants that map to the same
#'   abbreviation key are noted in a comment attribute on the result.
#' @noRd
.build_abbreviation_inventory <- function(text) {

  if (!nzchar(trimws(text))) return(stats::setNames(character(0), character(0)))

  # Match full binomials: Capitalised genus + lowercase epithet, optionally
  # followed by an author name in parentheses or plain.
  # Genus: 4+ chars to avoid false matches on short words.
  binomial_pat <- "\\b([A-Z][a-z]{3,})\\s+([a-z]{3,})(?:\\s+[a-z]{2,})?"

  full_matches <- gregexpr(binomial_pat, text, perl = TRUE)
  all_binomials <- regmatches(text, full_matches)[[1L]]

  if (length(all_binomials) == 0L) {
    return(stats::setNames(character(0), character(0)))
  }

  # Keep only binomials that appear more than once (candidates for abbreviation)
  binomial_counts <- table(trimws(all_binomials))
  candidates <- names(binomial_counts[binomial_counts > 1L])

  if (length(candidates) == 0L) {
    return(stats::setNames(character(0), character(0)))
  }

  # For each candidate binomial, build the expected abbreviation pattern
  # and confirm it appears in the text after the first full mention
  result_abbrev <- character(0)
  result_full   <- character(0)

  for (binomial in candidates) {
    parts <- strsplit(trimws(binomial), "\\s+")[[1L]]
    if (length(parts) < 2L) next

    genus   <- parts[1L]
    epithet <- parts[2L]
    abbrev  <- sprintf("%s. %s", substring(genus, 1L, 1L), epithet)

    # Check abbreviation actually appears in text
    abbrev_pat <- sprintf("\\b%s\\. %s\\b",
                          substring(genus, 1L, 1L), epithet)
    if (grepl(abbrev_pat, text, perl = TRUE)) {
      result_abbrev <- c(result_abbrev, abbrev)
      result_full   <- c(result_full,   sprintf("%s %s", genus, epithet))
    }
  }

  if (length(result_abbrev) == 0L) {
    return(stats::setNames(character(0), character(0)))
  }

  # ---- Fix #6: deduplicate by abbreviation key --------------------------------
  # Multiple full binomials can share the same abbreviation (e.g. different
  # Abudefduf species all abbreviate to "A. X", or a spelling variant like
  # "Valencienea" vs "Valenciennea" produces the same "V. sexguttata" key).
  # Keep the first full binomial encountered per abbreviation key.
  # Collect any variants that were dropped for transparency.
  seen_abbrevs  <- character(0)
  keep          <- logical(length(result_abbrev))
  variants      <- character(0)

  for (i in seq_along(result_abbrev)) {
    ab <- result_abbrev[i]
    if (!ab %in% seen_abbrevs) {
      seen_abbrevs <- c(seen_abbrevs, ab)
      keep[i]      <- TRUE
    } else {
      # Record the dropped variant for the comment attribute
      kept_full <- result_full[result_abbrev == ab][1L]
      if (result_full[i] != kept_full) {
        variants <- c(variants, sprintf("%s (variant of %s -> %s)",
                                        result_full[i], ab, kept_full))
      }
    }
  }

  result_abbrev <- result_abbrev[keep]
  result_full   <- result_full[keep]

  out <- stats::setNames(result_full, result_abbrev)

  # Attach spelling variants as an attribute for downstream inspection
  if (length(variants) > 0L) {
    attr(out, "spelling_variants") <- variants
  }

  out
}


# ==============================================================================
# Internal: .find_abstract_in_document()
# ==============================================================================

#' Extract abstract text from an undifferentiated document string
#'
#' When section header detection fails (has_headers = FALSE), the entire PDF
#' text is returned as a single "document" string. The first 3000 characters
#' are often author affiliations, journal metadata, and JSTOR/publisher
#' boilerplate rather than the actual abstract. This helper scans the document
#' text for the word "Abstract" (case-insensitive) as a standalone line or
#' inline label and returns the text that follows it, up to max_chars.
#'
#' Falls back to the first max_chars characters of the document if no
#' "Abstract" marker is found (e.g. very short notes with no explicit label).
#'
#' @param doc_text Character string. Full document text from pdf_content$sections$document.
#' @param max_chars Integer. Maximum characters to return. Default 3000L.
#'
#' @return Character string. Abstract text or first max_chars of document.
#' @noRd
.find_abstract_in_document <- function(doc_text, max_chars = 3000L) {

  if (!nzchar(trimws(doc_text))) return("")

  # Look for "Abstract" as: standalone line, or inline label followed by text
  # Patterns (case-insensitive):
  #   "Abstract\n..."          -- standalone header
  #   "Abstract.--..."          -- dash/em-dash inline label (common in older journals)
  #   "Abstract: ..."          -- colon label
  #   "ABSTRACT\n..."          -- all-caps standalone
  abs_pat <- "(?i)(?:^|\\n)\\s*abstract\\s*[.:\\----]?\\s*\\n?"

  m <- regexpr(abs_pat, doc_text, perl = TRUE)

  if (m == -1L) {
    # No Abstract marker found -- fall back to first max_chars
    return(substr(trimws(doc_text), 1L, max_chars))
  }

  # Start reading from end of the match
  start <- m + attr(m, "match.length")
  remaining <- substr(doc_text, start, nchar(doc_text))
  remaining <- trimws(remaining)

  # Take up to max_chars, stopping at the next likely section header
  # (all-caps line or known section keyword on its own line)
  lines <- strsplit(substr(remaining, 1L, max_chars * 2L), "\n")[[1L]]
  header_pat <- "^\\s*(introduction|methods|materials|results|keywords|" 
  header_pat <- paste0(header_pat, "INTRODUCTION|METHODS|MATERIALS|RESULTS|KEYWORDS)")

  end_line <- length(lines)
  for (i in seq_along(lines)) {
    if (i == 1L) next   # skip first line -- might be continuation of label line
    ln <- trimws(lines[i])
    if (grepl(header_pat, ln, ignore.case = TRUE) && nchar(ln) < 50L) {
      end_line <- i - 1L
      break
    }
  }

  result <- paste(lines[seq_len(end_line)], collapse = "\n")
  result <- trimws(result)

  if (nchar(result) > max_chars) substr(result, 1L, max_chars) else result
}


# ==============================================================================
# Internal: .build_characterize_prompt()
# ==============================================================================

#' Build the LLM prompt for five-axis paper characterization
#'
#' @param abstract_text Character. Abstract section text.
#' @param methods_text  Character. Methods section text (truncated if long).
#' @param results_text  Character. Results section text (may be empty string).
#' @param max_chars     Integer. Max chars per section to include in prompt.
#'   Default 3000L. Keeps token cost low while preserving enough context.
#'
#' @return Character string. Complete prompt ready for call_anthropic_api().
#' @noRd
.build_characterize_prompt <- function(abstract_text,
                                       methods_text,
                                       results_text,
                                       max_chars = 3000L) {

  # Truncate sections to token budget
  trunc <- function(txt, n) {
    if (!nzchar(trimws(txt))) return("(not available)")
    txt <- trimws(txt)
    if (nchar(txt) > n) paste0(substr(txt, 1L, n), "... [truncated]") else txt
  }

  abstract_trunc <- trunc(abstract_text, max_chars)
  methods_trunc  <- trunc(methods_text,  max_chars)
  results_trunc  <- trunc(results_text,  max_chars)

  sprintf(
'You are classifying a scientific paper to determine whether and how to extract
species occurrence records from it. Read the text below and respond ONLY with
a JSON object containing exactly these five keys. Do not include any text
outside the JSON object, no markdown fences, no preamble.

JSON keys and allowed values:

"observation_type": one of:
  "field_survey"          -- original field observations of organisms in the wild;
                             the paper reports where and when species were found
  "compilation_review"    -- synthesis or review of records from multiple sources
  "experimental_lab"      -- controlled lab or mesocosm experiment; location is an
                             institution, not a habitat
  "monitoring_time_series"-- repeated standardised sampling at fixed sites over time
  "prevalence_abundance"  -- study measuring infection rates, density, or abundance;
                             non-zero detections are valid occurrence records but
                             require special extraction handling
  "analytical_modelling"  -- paper analyses previously-collected data (food webs,
                             network metrics, statistical models, SDMs) without
                             reporting primary occurrence observations; the data
                             tables contain derived metrics, not species-locality
                             records; extraction is unlikely to yield DwC records

"location_structure": one of:
  "explicit_latlon"   -- coordinates (decimal degrees or DMS) given for records
  "named_localities"  -- records tied to named places, streams, counties, or stations
                         without explicit coordinates
  "split_tables"      -- species data and locality data in separate tables requiring
                         a join to link them
  "single_site"       -- all records from one study site (coordinates or name given once)

"data_density": one of:
  "tabular"      -- most data presented in formatted tables
  "prose_dense"  -- most data embedded in continuous prose (e.g. species accounts)
  "prose_sparse" -- brief mentions only; few data points
  "mixed"        -- substantial data in both tables AND extended prose species accounts
  "supplementary"-- primary data in supplementary files, not main text

"taxonomic_scope": one of:
  "single_species"   -- one focal species (host or target organism)
  "few_species"      -- 2-10 species total across ALL taxa for which occurrence
                        records could be extracted (count both hosts AND parasites
                        if both are reported with localities)
  "community_survey" -- 11 or more such species

"contamination_risk": one of:
  "high" -- Introduction or Discussion mentions many species comparatively or
            historically; risk of extracting non-observational records is high
  "low"  -- species mentions confined to results; low contamination risk

ABSTRACT:
%s

METHODS:
%s

RESULTS:
%s

Respond with only the JSON object.',
    abstract_trunc, methods_trunc, results_trunc
  )
}


# ==============================================================================
# Internal: .parse_structure_response()
# ==============================================================================

#' Parse the LLM JSON response for five-axis classifications
#'
#' Strips any accidental markdown fences and parses the JSON. Falls back to
#' heuristic NA values if parsing fails, with a warning.
#'
#' @param response_text Character. Raw LLM response string.
#'
#' @return Named list with elements: observation_type, location_structure,
#'   data_density, taxonomic_scope, contamination_risk. Each is a character
#'   string or NA_character_ on parse failure.
#' @noRd
.parse_structure_response <- function(response_text) {

  valid_values <- list(
    observation_type   = c("field_survey", "compilation_review",
                           "experimental_lab", "monitoring_time_series",
                           "prevalence_abundance", "analytical_modelling"),
    location_structure = c("explicit_latlon", "named_localities",
                           "split_tables", "single_site"),
    data_density       = c("tabular", "prose_dense", "prose_sparse",
                           "mixed", "supplementary"),
    taxonomic_scope    = c("single_species", "few_species", "community_survey"),
    contamination_risk = c("high", "low")
  )

  na_result <- lapply(names(valid_values), function(k) NA_character_)
  names(na_result) <- names(valid_values)

  # Strip markdown fences if present
  clean <- gsub("```json\\s*", "", response_text)
  clean <- gsub("```\\s*",     "", clean)
  clean <- trimws(clean)

  parsed <- tryCatch(
    jsonlite::fromJSON(clean, simplifyVector = TRUE),
    error = function(e) NULL
  )

  if (is.null(parsed) || !is.list(parsed)) {
    warning(
      "screen_pdf_structure: could not parse LLM JSON response. ",
      "All five axis values will be NA. Raw response:\n",
      substr(response_text, 1L, 300L),
      call. = FALSE
    )
    return(na_result)
  }

  # Validate each field; warn and set NA for unrecognised values
  result <- na_result
  for (key in names(valid_values)) {
    val <- parsed[[key]]
    if (is.null(val) || !is.character(val) || length(val) != 1L) {
      warning(sprintf(
        "screen_pdf_structure: LLM response missing or malformed field '%s' -- set to NA.",
        key
      ), call. = FALSE)
    } else if (!val %in% valid_values[[key]]) {
      warning(sprintf(
        paste0("screen_pdf_structure: unrecognised value '%s' for field '%s'. ",
               "Valid values: %s -- set to NA."),
        val, key, paste(valid_values[[key]], collapse = ", ")
      ), call. = FALSE)
    } else {
      result[[key]] <- val
    }
  }

  result
}


# ==============================================================================
# screen_pdf_structure()
# ==============================================================================

#' Characterize a PDF Paper on Five Axes for Occurrence Extraction
#'
#' Stage 2 of the PDF occurrence pipeline. Reads section texts from a
#' \code{\link{extract_pdf_text}} output object, classifies the paper on
#' five axes that control how Stage 3 extraction is configured, builds a
#' page-level table indicating which pages should be sent as images, and
#' constructs an inventory of Latin binomial abbreviations for use in the
#' extraction prompt.
#'
#' No PDF page images are sent in this stage. The LLM call (if enabled)
#' receives only plain text (abstract + methods + results), keeping token
#' cost low.
#'
#' @param pdf_content A named list as returned by
#'   \code{\link{extract_pdf_text}}. Must contain elements \code{$sections},
#'   \code{$page_map}, \code{$n_pages}, and \code{$has_headers}.
#' @param use_llm Logical. If \code{TRUE} (default), the five axis
#'   classifications are obtained from an LLM API call. If \code{FALSE},
#'   all five axes are set to \code{NA} and a warning is issued that results
#'   will be less reliable. Heuristic classification is not yet implemented;
#'   \code{use_llm = FALSE} is provided for testing and batch triage only.
#' @param llm_fn Function. The LLM call function to use. Must accept a single
#'   character string (the prompt) as its first argument and return a single
#'   character string (the response). Default \code{call_anthropic_api}.
#'   To use a different provider, pass a compatible wrapper function:
#'   \preformatted{
#'   my_openai <- function(prompt_str, ...) {
#'     # ... call OpenAI API ...
#'     return(response_text)
#'   }
#'   screen_pdf_structure(pdf_content, llm_fn = my_openai)
#'   }
#' @param model Character. Model identifier passed to \code{llm_fn}.
#'   Default \code{"claude-sonnet-4-6"} (cheaper than opus; sufficient for
#'   structured classification).
#' @param max_tokens Integer. Maximum response tokens for the LLM call.
#'   Default \code{400L} (JSON response is short).
#' @param api_key Character. API key passed to \code{llm_fn} when using the
#'   default \code{call_anthropic_api}. Reads from the
#'   \code{ANTHROPIC_API_KEY} environment variable. Ignored when a custom
#'   \code{llm_fn} is supplied.
#' @param verbose Logical. Report progress. Default \code{TRUE}.
#'
#' @return An S3 object of class \code{c("pdf_structure", "list")} with
#'   elements:
#'   \describe{
#'     \item{observation_type}{Character. One of: \code{"field_survey"},
#'       \code{"compilation_review"}, \code{"experimental_lab"},
#'       \code{"monitoring_time_series"}, \code{"prevalence_abundance"}.
#'       \code{NA} if classification failed.}
#'     \item{location_structure}{Character. One of: \code{"explicit_latlon"},
#'       \code{"named_localities"}, \code{"split_tables"},
#'       \code{"single_site"}. \code{NA} if classification failed.}
#'     \item{data_density}{Character. One of: \code{"tabular"},
#'       \code{"prose_dense"}, \code{"prose_sparse"},
#'       \code{"supplementary"}. \code{NA} if classification failed.}
#'     \item{taxonomic_scope}{Character. One of: \code{"single_species"},
#'       \code{"few_species"}, \code{"community_survey"}. \code{NA} if
#'       classification failed.}
#'     \item{contamination_risk}{Character. One of: \code{"high"},
#'       \code{"low"}. \code{NA} if classification failed.}
#'     \item{page_table}{Data frame with columns \code{page} (integer),
#'       \code{section} (character), \code{content_type} (character:
#'       \code{"prose"}, \code{"table"}, \code{"figure"}, \code{"mixed"},
#'       \code{"other"}), \code{legend_text} (character, \code{NA} if
#'       none), \code{send_image} (logical).}
#'     \item{abbreviation_inventory}{Named character vector. Names are
#'       abbreviated binomials (e.g. \code{"E. newberryi"}); values are the
#'       corresponding full binomials (e.g.
#'       \code{"Eucyclogobius newberryi"}). Zero-length if none detected.}
#'     \item{has_supplementary}{Logical. \code{TRUE} if the document
#'       contains an appendix or supplementary section.}
#'     \item{single_site_rule}{Logical. \code{TRUE} if
#'       \code{location_structure == "single_site"}, meaning Stage 3 should
#'       inject a single set of coordinates for all extracted records rather
#'       than expecting per-record locality fields.}
#'   }
#'
#' @details
#' \strong{Extraction decisions driven by axis values:}
#' \itemize{
#'   \item \code{observation_type == "experimental_lab"} or
#'     \code{"prevalence_abundance"} -> consider skipping extraction entirely
#'     (no DwC occurrence records expected).
#'   \item \code{data_density == "tabular"} -> Stage 3 should prioritise
#'     table pages (\code{send_image = TRUE} rows where
#'     \code{content_type == "table"}).
#'   \item \code{data_density == "prose_dense"} -> Stage 3 must read
#'     narrative text pages as images (species account style, like Swift
#'     et al. 1993).
#'   \item \code{contamination_risk == "high"} -> extraction prompt should
#'     explicitly instruct the model to skip Introduction and Discussion
#'     species mentions.
#'   \item \code{single_site_rule == TRUE} -> extraction prompt should note
#'     the single study site and inject its coordinates.
#' }
#'
#' \strong{Page table and send_image logic:}
#' Pages in \code{discussion}, \code{acknowledgements}, \code{funding}, and
#' \code{references} sections are always \code{send_image = FALSE}. Figure
#' pages are scored by legend keyword matching against an occurrence
#' vocabulary; figures without occurrence-relevant legends are skipped.
#' Table pages in core sections are always sent. Appendix pages are sent
#' only when \code{has_supplementary = TRUE}.
#'
#' \strong{No LLM fallback:}
#' When \code{use_llm = FALSE}, all five axis values are \code{NA}. There
#' is no heuristic classifier. This mode is intended for pipeline testing
#' and batch triage where cost must be minimised and imprecise
#' characterization is acceptable.
#'
#' \strong{Provider note:}
#' Only \code{call_anthropic_api} is provided as a built-in \code{llm_fn}.
#' Support for additional providers (OpenAI, Ollama, etc.) is a planned
#' future addition to \code{llm_api_utils.R}. In the meantime, any function
#' matching the \code{(prompt_str, model, max_tokens, api_key, ...)} signature
#' can be passed as \code{llm_fn}.
#'
#' @seealso \code{\link{extract_pdf_text}},
#'   \code{\link{build_pdf_extract_prompt}},
#'   \code{\link{call_anthropic_api_pdf}},
#'   \code{\link[TaxaTools]{call_anthropic_api}}
#'
#' @note \strong{Future task -- multi-provider support:} All LLM-calling
#'   functions in TaxaFetch should follow the \code{llm_fn} parameter
#'   pattern used here. Functions currently calling \code{call_anthropic_api}
#'   directly (e.g. \code{prompt_anthropic_api}) should be refactored to
#'   accept an \code{llm_fn} argument in a future session. New
#'   provider-specific functions (\code{call_openai_api},
#'   \code{call_ollama_api}) should be added to \code{llm_api_utils.R}.
#'
#' @importFrom TaxaTools call_anthropic_api
#' @export
#'
#' @examples
#' \dontrun{
#' pdf_content <- extract_pdf_text("Swift_et_al_1993.pdf")
#'
#' # Default: LLM classification via Anthropic API
#' structure <- screen_pdf_structure(pdf_content)
#' print(structure)
#'
#' # Inspect pages flagged for image send
#' structure$page_table[structure$page_table$send_image, ]
#'
#' # Check abbreviation inventory
#' structure$abbreviation_inventory
#'
#' # Skip LLM call (testing / triage mode)
#' structure <- screen_pdf_structure(pdf_content, use_llm = FALSE)
#'
#' # Use a custom LLM provider
#' my_llm <- function(prompt_str, model = "gpt-4o", max_tokens = 400,
#'                    api_key = Sys.getenv("OPENAI_API_KEY"), ...) {
#'   # ... OpenAI call ...
#' }
#' structure <- screen_pdf_structure(pdf_content, llm_fn = my_llm)
#' }

screen_pdf_structure <- function(pdf_content,
                                 use_llm    = TRUE,
                                 llm_fn     = getOption("TaxaID.llm_fn", call_anthropic_api),
                                 model      = "claude-sonnet-4-6",
                                 max_tokens = 400L,
                                 api_key    = Sys.getenv("ANTHROPIC_API_KEY"),
                                 verbose    = TRUE) {

  # ---- input validation -------------------------------------------------------
  if (!is.list(pdf_content) ||
      !all(c("sections", "page_map", "n_pages", "has_headers") %in%
           names(pdf_content))) {
    stop(
      "screen_pdf_structure: 'pdf_content' must be the list returned by ",
      "extract_pdf_text(). Required elements: $sections, $page_map, ",
      "$n_pages, $has_headers."
    )
  }
  if (!is.logical(use_llm) || length(use_llm) != 1L || is.na(use_llm)) {
    stop("screen_pdf_structure: 'use_llm' must be TRUE or FALSE.")
  }
  if (!is.function(llm_fn)) {
    stop("screen_pdf_structure: 'llm_fn' must be a function.")
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("screen_pdf_structure: 'verbose' must be TRUE or FALSE.")
  }
  max_tokens <- as.integer(max_tokens)

  # ---- API key check (warn, do not stop -- fallback to NA axes) ----------------
  using_default_fn <- identical(llm_fn, call_anthropic_api)
  if (use_llm && using_default_fn && !nzchar(api_key)) {
    warning(
      "screen_pdf_structure: ANTHROPIC_API_KEY is not set. ",
      "The LLM classification call will fail.\n",
      "Set it with: Sys.setenv(ANTHROPIC_API_KEY = 'sk-ant-...')\n",
      "or add ANTHROPIC_API_KEY=sk-ant-... to your ~/.Renviron file.\n",
      "Falling back to NA axis values (use_llm treated as FALSE).\n",
      "To use a different LLM provider, pass a compatible function as llm_fn.",
      call. = FALSE
    )
    use_llm <- FALSE
  }

  # ---- extract section texts --------------------------------------------------
  secs <- pdf_content$sections

  abstract_text <- secs$abstract %||% ""
  methods_text  <- secs$methods  %||% ""
  results_text  <- secs$results  %||% ""

  # Fallback: if no recognised sections, use "document"
  # Use .find_abstract_in_document() to scan past author/journal metadata
  # and find the actual abstract text -- critical for two-column journal PDFs
  # where section headers are not detected.
  if (!nzchar(trimws(abstract_text)) &&
      !nzchar(trimws(methods_text))  &&
      !nzchar(trimws(results_text))) {
    doc_text      <- secs$document %||% ""
    abstract_text <- .find_abstract_in_document(doc_text, max_chars = 3000L)
    methods_text  <- ""
    results_text  <- ""
  }

  # ---- detect supplementary ---------------------------------------------------
  has_supplementary <- !is.null(pdf_content$page_map$appendix) &&
                       length(pdf_content$page_map$appendix) > 0L

  # ---- five-axis LLM classification -------------------------------------------
  axes <- list(
    observation_type   = NA_character_,
    location_structure = NA_character_,
    data_density       = NA_character_,
    taxonomic_scope    = NA_character_,
    contamination_risk = NA_character_
  )

  if (use_llm) {
    if (verbose) {
      message("screen_pdf_structure: calling LLM for five-axis classification...")
    }

    prompt_str <- .build_characterize_prompt(
      abstract_text = abstract_text,
      methods_text  = methods_text,
      results_text  = results_text
    )

    raw_response <- tryCatch(
      llm_fn(prompt_str,
             model      = model,
             max_tokens = max_tokens,
             api_key    = api_key),
      error = function(e) {
        warning(sprintf(
          "screen_pdf_structure: LLM call failed -- %s\nFalling back to NA axis values.",
          conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )

    if (!is.null(raw_response)) {
      axes <- .parse_structure_response(raw_response)
    }

  } else {
    if (verbose) {
      message(
        "screen_pdf_structure: use_llm = FALSE -- ",
        "all five axis values set to NA. ",
        "Set use_llm = TRUE for reliable classification."
      )
    }
  }

  # ---- page table (text-layer, no API) ----------------------------------------
  if (verbose) {
    message("screen_pdf_structure: building page table...")
  }

  # Reconstruct raw page texts -- need pdftools for this; use pdf_path if available
  # The page table requires per-page text which is not stored in pdf_content.
  # We re-extract from pdf_path (stored in pdf_content$pdf_path) using pdftools,
  # then truncate to pdf_content$n_pages to respect any boundary truncation that
  # extract_pdf_text() applied (e.g. journal back matter removed). Without this
  # truncation, the page table would have more rows than the page_map covers,
  # causing the print method to report the wrong total page count.
  pages_text <- NULL
  if (!is.null(pdf_content$pdf_path) && nzchar(pdf_content$pdf_path) &&
      file.exists(pdf_content$pdf_path)) {
    if (requireNamespace("pdftools", quietly = TRUE)) {
      pages_text <- tryCatch(
        pdftools::pdf_text(pdf_content$pdf_path),
        error = function(e) {
          warning(sprintf(
            "screen_pdf_structure: could not re-read PDF for page table: %s",
            conditionMessage(e)
          ), call. = FALSE)
          NULL
        }
      )
      # Truncate to match boundary-truncated pdf_content
      if (!is.null(pages_text) &&
          length(pages_text) > pdf_content$n_pages) {
        pages_text <- pages_text[seq_len(pdf_content$n_pages)]
      }
    }
  }

  if (is.null(pages_text)) {
    # Cannot build page table without page-level text
    warning(
      "screen_pdf_structure: per-page text not available -- ",
      "page_table will have no rows. ",
      "Ensure pdf_content$pdf_path points to the original PDF file.",
      call. = FALSE
    )
    page_tbl <- data.frame(
      page         = integer(0),
      section      = character(0),
      content_type = character(0),
      legend_text  = character(0),
      send_image   = logical(0),
      stringsAsFactors = FALSE
    )
  } else {
    page_tbl <- .build_page_table(
      pages_text        = pages_text,
      page_map          = pdf_content$page_map,
      has_supplementary = has_supplementary
    )
  }

  # ---- abbreviation inventory -------------------------------------------------
  # Use the richest available text: prefer specific section texts, but fall
  # back to secs$document when has_headers = FALSE (two-column layouts where
  # pdftools collapses the whole PDF into one undifferentiated block).
  # This ensures abbreviations are found even when section detection failed.
  combined_text <- paste(
    abstract_text, methods_text, results_text,
    sep = "\n"
  )
  if (!nzchar(trimws(combined_text)) || !pdf_content$has_headers) {
    doc_text      <- pdf_content$sections$document %||% ""
    combined_text <- paste(combined_text, doc_text, sep = "\n")
  }
  abbrev_inventory <- .build_abbreviation_inventory(combined_text)

  # ---- single_site_rule -------------------------------------------------------
  single_site_rule <- identical(axes$location_structure, "single_site")

  # ---- warn on observation types unlikely to yield DwC records ---------------
  obs_type <- axes$observation_type
  if (!is.na(obs_type) &&
      obs_type %in% c("experimental_lab", "analytical_modelling")) {
    warning(sprintf(
      paste0("screen_pdf_structure: observation_type = '%s'. ",
             "This paper type is unlikely to yield DwC occurrence records. ",
             "Consider skipping Stage 3 extraction."),
      obs_type
    ), call. = FALSE)
  }

  # ---- assemble and return ----------------------------------------------------
  if (verbose) {
    n_send <- if (nrow(page_tbl) > 0L) sum(page_tbl$send_image) else 0L
    message(sprintf(
      "screen_pdf_structure: complete. %d page(s) flagged for image send; %d abbreviation(s) found.",
      n_send, length(abbrev_inventory)
    ))
  }

  structure(
    list(
      pdf_path              = pdf_content$pdf_path,
      observation_type      = axes$observation_type,
      location_structure    = axes$location_structure,
      data_density          = axes$data_density,
      taxonomic_scope       = axes$taxonomic_scope,
      contamination_risk    = axes$contamination_risk,
      page_table            = page_tbl,
      abbreviation_inventory = abbrev_inventory,
      has_supplementary     = has_supplementary,
      single_site_rule      = single_site_rule
    ),
    class = c("pdf_structure", "list")
  )
}


# ==============================================================================
# print.pdf_structure
# ==============================================================================

#' Print method for pdf_structure objects
#'
#' @param x A \code{pdf_structure} object from \code{\link{screen_pdf_structure}}.
#' @param ... Ignored.
#' @export
#' @noRd
print.pdf_structure <- function(x, ...) {

  na_str <- function(v) if (is.na(v)) "(NA -- LLM not run or failed)" else v

  cat("<pdf_structure>\n")
  cat(sprintf("  observation_type   : %s\n", na_str(x$observation_type)))
  cat(sprintf("  location_structure : %s\n", na_str(x$location_structure)))
  cat(sprintf("  data_density       : %s\n", na_str(x$data_density)))
  cat(sprintf("  taxonomic_scope    : %s\n", na_str(x$taxonomic_scope)))
  cat(sprintf("  contamination_risk : %s\n", na_str(x$contamination_risk)))
  cat(sprintf("  has_supplementary  : %s\n", x$has_supplementary))
  cat(sprintf("  single_site_rule   : %s\n", x$single_site_rule))

  if (nrow(x$page_table) > 0L) {
    n_send  <- sum(x$page_table$send_image)
    n_total <- nrow(x$page_table)
    n_tbl   <- sum(x$page_table$content_type == "table")
    n_fig   <- sum(x$page_table$content_type == "figure")
    cat(sprintf(
      "  page_table         : %d pages total; %d flagged for image send (%d table, %d figure)\n",
      n_total, n_send, n_tbl, n_fig
    ))
  } else {
    cat("  page_table         : (not available)\n")
  }

  n_abbrev <- length(x$abbreviation_inventory)
  if (n_abbrev > 0L) {
    cat(sprintf("  abbreviations      : %d found", n_abbrev))
    show_n <- min(n_abbrev, 4L)
    previews <- sprintf("%s -> %s",
                        names(x$abbreviation_inventory)[seq_len(show_n)],
                        x$abbreviation_inventory[seq_len(show_n)])
    cat(sprintf(" (%s%s)\n",
                paste(previews, collapse = "; "),
                if (n_abbrev > 4L) "; ..." else ""))
    variants <- attr(x$abbreviation_inventory, "spelling_variants")
    if (!is.null(variants) && length(variants) > 0L) {
      cat(sprintf("  spelling variants  : %s\n",
                  paste(head(variants, 3L), collapse = "; ")))
    }
  } else {
    cat("  abbreviations      : none detected\n")
  }

  # Extraction notes
  obs  <- x$observation_type
  dens <- x$data_density
  if (!is.na(obs)) {
    note <- switch(obs,
      analytical_modelling  = "  [!] analytical_modelling -- extraction unlikely to yield DwC records\n",
      experimental_lab      = "  [!] experimental_lab -- location is institution; extraction not recommended\n",
      prevalence_abundance  = "  [i] prevalence_abundance -- non-zero detections extractable as occurrences\n",
      NULL
    )
    if (!is.null(note)) cat(note)
  }
  if (!is.na(dens) && dens == "supplementary") {
    cat("  [i] supplementary -- primary data may be in a separate file\n")
  }
  if (isTRUE(x$contamination_risk == "high")) {
    cat("  [i] contamination_risk = high -- extraction prompt must exclude Intro/Discussion\n")
  }
  if (isTRUE(x$single_site_rule)) {
    cat("  [i] single_site_rule -- inject single-site coordinates in extraction prompt\n")
  }

  invisible(x)
}
