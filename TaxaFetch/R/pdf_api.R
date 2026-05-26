# ==============================================================================
# pdf_api.R
# TaxaFetch — Send PDF page images to the Anthropic API
#
# Exported functions:
#   call_anthropic_api_pdf()    Send selected PDF pages as images to API
#
# Internal helpers (@noRd):
#   .render_pdf_pages()         Render page numbers to base64 PNG images
#
# Relationship to DataONE pipeline:
#   Extends call_anthropic_api() (in llm_api_utils.R) to handle document
#   input. call_anthropic_api() handles text-in/text-out. This function
#   handles PDF-page-images-in/text-out. Both return a single character
#   string suitable for passing to parse_*_response() functions.
#
#   The section targeting here (sending only methods + results pages) is
#   the PDF pipeline equivalent of the EML column screening step in
#   screen_eml_columns() — both are designed to avoid committing to
#   expensive processing on irrelevant content.
#
# Dependencies:
#   pdftools (Suggests) — pdf_render_page() for image rendering
#   httr2    (Imports)  — API call (same as call_anthropic_api)
#   jsonlite (Imports)  — JSON construction
#
# Token cost notes:
#   Each rendered page costs approx 1,500-2,000 input tokens.
#   Targeting 4-8 pages (methods + results) vs full document (10-20 pages)
#   saves 50-70% of input tokens for a typical journal article.
# ==============================================================================


# ==============================================================================
# Internal: .render_pdf_pages()
# ==============================================================================

#' Render selected PDF pages to base64-encoded PNG strings
#'
#' @param pdf_path Character. Path to PDF file.
#' @param page_numbers Integer vector. Pages to render (1-based).
#' @param dpi Integer. Rendering resolution. Default 150L. Higher values
#'   improve table readability but increase token cost. 150 dpi is a good
#'   balance for printed journal text.
#'
#' @return Named list of base64-encoded PNG strings, named by page number.
#' @noRd
.render_pdf_pages <- function(pdf_path, page_numbers, dpi = 150L) {

  if (!requireNamespace("pdftools", quietly = TRUE)) {
    stop(
      ".render_pdf_pages: the 'pdftools' package is required.\n",
      "Install it with: install.packages(\"pdftools\")"
    )
  }
  if (!requireNamespace("png", quietly = TRUE)) {
    stop(
      ".render_pdf_pages: the 'png' package is required.\n",
      "Install it with: install.packages(\"png\")"
    )
  }
  if (!requireNamespace("base64enc", quietly = TRUE)) {
    stop(
      ".render_pdf_pages: the 'base64enc' package is required.\n",
      "Install it with: install.packages(\"base64enc\")"
    )
  }

  # Use subprocess rendering if callr is available — protects against segfaults
  # from corrupt PDFs that crash poppler/pdftools at the C level.
  use_subprocess <- requireNamespace("callr", quietly = TRUE)

  results <- vector("list", length(page_numbers))
  names(results) <- as.character(page_numbers)

  for (i in seq_along(page_numbers)) {
    pg <- page_numbers[i]

    if (use_subprocess) {
      # Render in isolated subprocess — segfault kills child, not parent
      b64 <- tryCatch(
        callr::r(
          function(pdf_path, pg, dpi) {
            img <- pdftools::pdf_render_page(pdf_path, page = pg, dpi = dpi,
                                             numeric = FALSE)
            tmp <- tempfile(fileext = ".png")
            on.exit(unlink(tmp), add = TRUE)
            png::writePNG(img, tmp)
            raw_bytes <- readBin(tmp, "raw", file.info(tmp)$size)
            base64enc::base64encode(raw_bytes)
          },
          args = list(pdf_path = pdf_path, pg = pg, dpi = dpi),
          timeout = 60
        ),
        error = function(e) {
          warning(sprintf(
            ".render_pdf_pages: page %d crashed or timed out (subprocess): %s",
            pg, conditionMessage(e)
          ), call. = FALSE)
          NULL
        }
      )
    } else {
      # Fallback: render in-process (segfault will crash R)
      b64 <- tryCatch({
        img <- pdftools::pdf_render_page(pdf_path, page = pg, dpi = dpi,
                                         numeric = FALSE)
        tmp <- tempfile(fileext = ".png")
        on.exit(unlink(tmp), add = TRUE)
        png::writePNG(img, tmp)
        raw_bytes <- readBin(tmp, "raw", file.info(tmp)$size)
        base64enc::base64encode(raw_bytes)
      }, error = function(e) {
        warning(sprintf(".render_pdf_pages: could not render page %d: %s",
                        pg, conditionMessage(e)), call. = FALSE)
        NULL
      })
    }

    results[[i]] <- b64
  }

  # Drop failed pages
  results[!vapply(results, is.null, logical(1L))]
}


# ==============================================================================
# call_anthropic_api_pdf()
# ==============================================================================

#' Send Selected PDF Pages to an LLM Vision API
#'
#' Renders selected pages of a PDF as PNG images and sends them to a
#' vision-capable LLM together with a text prompt. Returns the model's
#' response as a single character string, compatible with all downstream
#' parse functions.
#'
#' This is the Stage 3 engine for the PDF occurrence pipeline. Stages 1 and 2
#' use \code{\link{extract_pdf_text}} (text only, no API call). Stage 3 uses
#' this function to send the methods and results pages as images, giving the
#' model full visual fidelity on tables and layout.
#'
#' Dispatches via \code{\link[TaxaTools]{call_api}}, so the provider is
#' resolved from \code{options("TaxaID.provider")} by default. Any
#' vision-capable provider works: Anthropic (Claude Sonnet/Opus), Gemini
#' (2.5 Flash/Pro), OpenAI (GPT-4o), or a local Ollama vision model such as
#' \code{llava-llama3}.
#'
#' @param prompt Character string. The extraction or characterization prompt
#'   to send along with the page images. This is the text part of the
#'   message; the images follow as separate content blocks.
#' @param pdf_path Character string. Path to the PDF file.
#' @param sections Character vector. Section labels whose pages should be
#'   rendered and sent. Default \code{c("methods", "results", "appendix")}.
#'   Only sections present in \code{page_map} are used; others are silently
#'   skipped. Pass \code{"all"} to send the entire document (expensive).
#' @param page_map Named list mapping section labels to integer page vectors,
#'   as returned in \code{extract_pdf_text()$page_map}. If \code{NULL}
#'   (default), \code{extract_pdf_text()} is called internally. Pass a
#'   pre-computed page_map to avoid re-parsing the PDF when Stage 2 has
#'   already run.
#' @param dpi Integer. Rendering resolution in dots per inch. Default
#'   \code{150L}. Increase to \code{200L} or \code{300L} for PDFs with
#'   small table fonts; decrease to \code{100L} to reduce token cost when
#'   tables are large-print.
#' @param provider Character. LLM provider name: \code{"anthropic"},
#'   \code{"gemini"}, \code{"openai"}, \code{"ollama"}, or any provider
#'   registered with \code{\link[TaxaTools]{register_provider}}. Default
#'   \code{NULL} reads \code{options("TaxaID.provider")}, set automatically
#'   by \code{library(TaxaTools)}.
#' @param tier Character. Model capability tier when \code{model = NULL}:
#'   \code{"fast"}, \code{"mid"} (default), or \code{"top"}. For vision
#'   tasks, \code{"mid"} or \code{"top"} is recommended.
#' @param model Character. Exact model identifier. Overrides \code{tier}
#'   resolution. Use to pin a specific version, e.g.
#'   \code{"claude-sonnet-4-6"} or \code{"gpt-4o"}.
#' @param max_tokens Integer. Maximum response tokens. Default \code{4000L}.
#'   Increase for papers with many species-locality records.
#' @param api_key Character. API key override. Default \code{NULL} reads
#'   the key from the environment variable for the resolved provider
#'   (e.g. \code{ANTHROPIC_API_KEY}). Keyless providers (Ollama) ignore this.
#' @param base_url Character. Base URL override for OpenAI-compatible
#'   providers (Ollama, custom proxies). Default \code{NULL}.
#' @param verbose Logical. Report page counts and section selection.
#'   Default \code{TRUE}.
#'
#' @return Character string. The raw text response from the model, suitable
#'   for passing directly to \code{\link{parse_pdf_extract_response}} or
#'   \code{\link{screen_pdf_structure}}. The \code{"model"} and
#'   \code{"provider"} attributes from \code{\link[TaxaTools]{call_api}} are
#'   preserved on the return value.
#'
#' @details
#' \strong{Page selection:} Only pages belonging to the requested sections
#' (as determined by \code{.detect_pdf_sections}) are rendered and sent.
#' For a typical 15-page methods paper this reduces the page count from
#' ~15 to ~5, saving approximately 15,000 input tokens per call.
#'
#' \strong{Page ordering:} Pages are sent in document order regardless of
#' section order, so the model sees a coherent reading sequence.
#'
#' \strong{No-header fallback:} If section headers were not detected
#' (\code{has_headers = FALSE}), all pages are sent regardless of the
#' \code{sections} argument, and a warning is issued.
#'
#' \strong{Token cost estimate:} At 150 dpi, each page image is
#' approximately 1,500-2,000 input tokens. A 5-page targeted send costs
#' roughly 8,000-10,000 input tokens plus the prompt.
#'
#' \strong{Provider and model selection:}
#' The function dispatches through \code{\link[TaxaTools]{call_api}}, so
#' provider resolution, model tier lookup, and API key reading follow the
#' same rules as all other TaxaID LLM calls. Set
#' \code{options(TaxaID.provider = "gemini")} to switch providers
#' session-wide, or pass \code{provider} explicitly for a single call.
#'
#' @seealso \code{\link[TaxaTools]{call_api}},
#'   \code{\link{extract_pdf_text}},
#'   \code{\link{build_pdf_extract_prompt}},
#'   \code{\link{screen_pdf_structure}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Typical Stage 3 usage — page_map from Stage 2:
#' pdf_content <- extract_pdf_text("Swift_et_al_1993.pdf")
#'
#' prompt <- build_pdf_extract_prompt(
#'   pdf_meta   = my_screen_result,
#'   taxon_scope = "freshwater fish",
#'   bbox        = c(-122, -117, 32, 35)
#' )
#'
#' raw_response <- call_anthropic_api_pdf(
#'   prompt   = prompt,
#'   pdf_path = "Swift_et_al_1993.pdf",
#'   page_map = pdf_content$page_map
#' )
#'
#' occurrences <- parse_pdf_extract_response(raw_response)
#'
#' # Higher resolution for a paper with dense tables:
#' raw_response <- call_anthropic_api_pdf(
#'   prompt   = prompt,
#'   pdf_path = "dense_tables_paper.pdf",
#'   page_map = pdf_content$page_map,
#'   dpi      = 250L
#' )
#' }

call_anthropic_api_pdf <- function(prompt,
                                   pdf_path,
                                   sections   = c("methods", "results",
                                                  "appendix"),
                                   page_map   = NULL,
                                   dpi        = 150L,
                                   provider   = NULL,
                                   tier       = c("mid", "fast", "top"),
                                   model      = NULL,
                                   max_tokens = 4000L,
                                   api_key    = NULL,
                                   base_url   = NULL,
                                   verbose    = TRUE) {

  # ---- input checks ----------------------------------------------------------
  if (!is.character(prompt) || length(prompt) != 1L ||
      is.na(prompt) || !nzchar(trimws(prompt))) {
    stop("call_anthropic_api_pdf: 'prompt' must be a non-empty character string.")
  }
  if (!is.character(pdf_path) || length(pdf_path) != 1L ||
      is.na(pdf_path) || !nzchar(trimws(pdf_path))) {
    stop("call_anthropic_api_pdf: 'pdf_path' must be a non-empty character string.")
  }
  if (!file.exists(pdf_path)) {
    stop(sprintf("call_anthropic_api_pdf: file not found: %s", pdf_path))
  }
  if (!is.character(sections) || length(sections) == 0L) {
    stop("call_anthropic_api_pdf: 'sections' must be a non-empty character vector or \"all\".")
  }
  if (!is.null(page_map) && !is.list(page_map)) {
    stop("call_anthropic_api_pdf: 'page_map' must be a named list or NULL.")
  }
  tier       <- match.arg(tier)
  dpi        <- as.integer(dpi)
  max_tokens <- as.integer(max_tokens)

  # ---- build page_map if not supplied ----------------------------------------
  if (is.null(page_map)) {
    if (verbose) {
      message("call_anthropic_api_pdf: no page_map supplied -- running extract_pdf_text() internally.")
    }
    pdf_content <- extract_pdf_text(pdf_path, sections = "all",
                                    verbose = verbose)
    page_map    <- pdf_content$page_map
  }

  has_headers <- attr(page_map, "has_headers") %||% TRUE

  # ---- select pages ----------------------------------------------------------
  if (!has_headers) {
    warning(
      "call_anthropic_api_pdf: no section headers detected in PDF -- sending all pages.",
      call. = FALSE
    )
    selected_pages <- sort(unique(unlist(page_map)))
  } else if (identical(sections, "all")) {
    selected_pages <- sort(unique(unlist(page_map)))
  } else {
    available <- intersect(sections, names(page_map))
    if (length(available) == 0L) {
      warning(
        sprintf(
          "call_anthropic_api_pdf: none of the requested sections (%s) were detected -- sending all pages.",
          paste(sections, collapse = ", ")
        ),
        call. = FALSE
      )
      selected_pages <- sort(unique(unlist(page_map)))
    } else {
      selected_pages <- sort(unique(unlist(page_map[available])))
      if (verbose) {
        skipped <- setdiff(sections, names(page_map))
        message(sprintf(
          "call_anthropic_api_pdf: sending %d page(s) from sections: %s%s",
          length(selected_pages),
          paste(available, collapse = ", "),
          if (length(skipped) > 0L)
            sprintf(" (not found: %s)", paste(skipped, collapse = ", "))
          else ""
        ))
      }
    }
  }

  # ---- render pages to base64 PNG --------------------------------------------
  if (verbose) {
    message(sprintf(
      "call_anthropic_api_pdf: rendering %d page(s) at %d dpi...",
      length(selected_pages), dpi
    ))
  }

  page_images <- .render_pdf_pages(pdf_path, selected_pages, dpi = dpi)

  if (length(page_images) == 0L) {
    stop("call_anthropic_api_pdf: no pages could be rendered. Check that the PDF is not encrypted or corrupted.")
  }

  if (verbose) {
    message(sprintf(
      "call_anthropic_api_pdf: %d page(s) rendered successfully.",
      length(page_images)
    ))
  }

  # ---- dispatch via call_api with vision images ------------------------------
  # page_images is a named list of base64 PNG strings (names = page numbers).
  # call_api() formats them for each provider family:
  #   anthropic     -> image content blocks (type/source/base64)
  #   gemini        -> inlineData parts (mimeType/data)
  #   openai_compat -> image_url blocks  (data:image/png;base64,...)
  TaxaTools::call_api(
    prompt_str = prompt,
    provider   = provider,
    tier       = tier,
    model      = model,
    max_tokens = max_tokens,
    api_key    = api_key,
    base_url   = base_url,
    images     = page_images
  )
}
