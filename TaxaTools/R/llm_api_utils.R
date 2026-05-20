# ==============================================================================
# llm_api_utils.R
# TaxaTools — LLM provider utilities
#
# Exported functions:
#   call_anthropic_api()    Provider: Anthropic — one prompt string -> one response string
#   call_gemini_api()       Provider: Google Gemini — one prompt string -> one response string
#   call_openai_api()       Provider: OpenAI — one prompt string -> one response string
#   call_ollama_api()       Provider: Ollama (local) — one prompt string -> one response string
#   prompt_api()            Multi-chunk llm_prompt dispatcher; llm_fn param selects provider
#   prompt_manual()         Manual file handoff (any provider)
#   read_llm_response()     Read saved response file(s)
#
# Internal helpers (all @noRd):
#   .call_api_single()      Call llm_fn(prompt_str) for one chunk
#   .combine_chunk_responses()  Concatenate multi-chunk responses
#   %||%                    Null-coalescing operator
#
# S3 dispatch note:
#   prompt_api() and prompt_manual() accept any object that inherits
#   from "llm_prompt" (the shared base class). Both habitat_prompt and
#   geo_prompt carry this class, so both work without any changes here.
#
# Provider API keys (set in ~/.Renviron):
#   ANTHROPIC_API_KEY  — required for call_anthropic_api() (no free tier)
#   GEMINI_API_KEY     — required for call_gemini_api() (free tier available)
#   OPENAI_API_KEY     — required for call_openai_api() (no ongoing free tier)
#   (none)             — call_ollama_api() needs no key; runs models locally
# ==============================================================================


# ==============================================================================
# Generic Anthropic API call -- one string in, one string out
# ==============================================================================

#' Call the Anthropic API with a Single Prompt String
#'
#' Low-level generic function: submits one plain character string to the
#' Anthropic Messages API and returns the model's response as a plain
#' character string. No chunking, no S3 class requirements, no
#' domain-specific logic.
#'
#' Use this directly when you have already built your own prompt string
#' (e.g. for geographic screening, PDF extraction, or any ad-hoc task).
#' For habitat assignment with a \code{build_habitat_prompt()} (TaxaHabitat) object,
#' use \code{\link{prompt_api}} instead -- it handles chunking and
#' per-chunk retries automatically.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Anthropic model identifier.
#'   Default \code{"claude-opus-4-6"}.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   Sufficient for most taxonomy and habitat prompts. Increase for longer
#'   outputs (e.g., large species lists). Higher values increase API cost.
#' @param api_key Character. Anthropic API key. Defaults to the
#'   \code{ANTHROPIC_API_KEY} environment variable.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops on any non-200 HTTP status.
#'
#' @seealso \code{\link{prompt_api}} for multi-chunk
#'   \code{llm_prompt} submission.
#'   \code{\link{call_gemini_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_ollama_api}} for alternative providers.
#'
#' @importFrom httr2 request req_headers req_body_json req_error req_perform
#'   resp_status resp_body_json
#' @export
#'
#' @examples
#' \dontrun{
#' Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-...")
#' answer <- call_anthropic_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_anthropic_api <- function(prompt_str,
                               model      = "claude-opus-4-6",
                               max_tokens = 3000L,
                               api_key    = Sys.getenv("ANTHROPIC_API_KEY")) {

  if (!is.character(prompt_str) || length(prompt_str) != 1L) {
    stop("call_anthropic_api: 'prompt_str' must be a length-1 character string.")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("call_anthropic_api: package 'httr2' is required. ",
         "Install with: install.packages('httr2')")
  }
  if (!nzchar(api_key)) {
    stop(
      "call_anthropic_api: no API key found.\n",
      "Set ANTHROPIC_API_KEY in your .Renviron file or with:\n",
      "  Sys.setenv(ANTHROPIC_API_KEY = 'sk-ant-...')"
    )
  }

  resp <- httr2::request("https://api.anthropic.com/v1/messages") |>
    httr2::req_headers(
      "x-api-key"         = api_key,
      "anthropic-version" = "2023-06-01",  # Anthropic Messages API version; update if API changes
      "content-type"      = "application/json"
    ) |>
    httr2::req_body_json(list(
      model      = model,
      max_tokens = max_tokens,
      messages   = list(list(role = "user", content = prompt_str))
    )) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf(
      "call_anthropic_api: HTTP %d: %s",
      status,
      body$error$message %||% "(no message)"
    ))
  }

  body        <- httr2::resp_body_json(resp)
  text_blocks <- Filter(function(b) identical(b$type, "text"), body$content)

  if (length(text_blocks) == 0L) {
    stop("call_anthropic_api: API response contained no text blocks.")
  }

  out <- text_blocks[[1]]$text
  attr(out, "model") <- model
  out
}


# ==============================================================================
# STEP 2 -- PATH 1: Multi-chunk llm_prompt dispatcher (provider-neutral)
# ==============================================================================

#' Submit a Multi-Chunk LLM Prompt to Any Provider
#'
#' Submits an \code{llm_prompt} object to an LLM provider,
#' handling multi-chunk prompts automatically. Provider is selected via the
#' \code{llm_fn} argument, which defaults to \code{\link{call_anthropic_api}}
#' but accepts any function with the signature
#' \code{function(prompt_str, ...) -> character(1)}.
#'
#' Returns the combined raw response text from all chunks for passing to
#' a response parser such as
#' \code{parse_hierarchical_habitat_response()} (TaxaHabitat).
#'
#' @param prompt An \code{llm_prompt} object (e.g. from
#'   \code{build_habitat_prompt()} (TaxaHabitat)).
#' @param llm_fn Function. A provider function that accepts a single character
#'   string (the prompt) and returns a single character string (the response).
#'   Default: \code{\link{call_anthropic_api}}.
#'   Built-in alternatives: \code{\link{call_gemini_api}},
#'   \code{\link{call_openai_api}}, \code{\link{call_ollama_api}}.
#'   To use a non-default model or API key, pass a closure:
#'   \preformatted{
#'   my_gemini <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash")
#'   raw_text  <- prompt_api(prompt, llm_fn = my_gemini)
#'   }
#' @param pause_seconds Numeric. Seconds to pause between chunks to avoid
#'   rate limits. Default 1.
#' @param verbose Logical. Print progress per chunk. Default \code{TRUE}.
#'
#' @return A length-1 character string containing the combined raw response
#'   text from all chunks.
#'
#' @details
#' \strong{Prompt types in TaxaID:}
#' The term "prompt" has two distinct meanings in the ecosystem:
#' \itemize{
#'   \item \strong{llm_prompt S3 object}: A structured multi-chunk prompt
#'     created by domain functions (e.g., \code{build_habitat_prompt()} in
#'     TaxaHabitat). Contains chunked prompts, metadata, and taxa lists.
#'     Used by \code{prompt_api()} and \code{prompt_manual()}.
#'   \item \strong{Plain character string}: A single text prompt passed
#'     directly to provider functions (\code{call_anthropic_api()}, etc.)
#'     or to \code{draft_methods_text()} / \code{draft_results_text()}.
#' }
#' \code{prompt_api()} requires the S3 object; the individual provider
#' functions accept plain strings.
#'
#' \strong{Provider selection:} All provider-specific concerns (API keys,
#' model names, token limits) belong inside the \code{llm_fn} function.
#' Use a closure to fix non-default parameters for any provider:
#' \preformatted{
#' # Anthropic with a non-default model
#' my_fn <- function(p, ...) call_anthropic_api(p, model = "claude-haiku-4-5-20251001")
#'
#' # Gemini free tier
#' my_fn <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash")
#'
#' # Local Ollama model
#' my_fn <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b")
#'
#' raw_text <- prompt_api(prompt, llm_fn = my_fn)
#' }
#'
#' @seealso \code{\link{call_anthropic_api}}, \code{\link{call_gemini_api}},
#'   \code{\link{call_openai_api}}, \code{\link{call_ollama_api}},
#'   \code{\link{prompt_manual}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # With TaxaHabitat
#' prompt <- TaxaHabitat::build_habitat_prompt(c("Gadus morhua", "Sebastes mystinus"))
#'
#' # Anthropic (default)
#' raw_text <- prompt_api(prompt)
#'
#' # Gemini free tier
#' raw_text <- prompt_api(prompt, llm_fn = call_gemini_api)
#'
#' # Local Ollama
#' raw_text <- prompt_api(prompt, llm_fn = call_ollama_api)
#' }

prompt_api <- function(prompt,
                       llm_fn        = call_anthropic_api,
                       pause_seconds = 1,
                       verbose       = TRUE) {

  if (!inherits(prompt, "llm_prompt")) {
    stop("prompt_api: 'prompt' must be an llm_prompt object ",
         "(e.g. from build_habitat_prompt() or build_geo_prompt()).")
  }
  if (!is.function(llm_fn)) {
    stop("prompt_api: 'llm_fn' must be a function with signature ",
         "function(prompt_str, ...) -> character(1). ",
         "Use call_anthropic_api, call_gemini_api, call_openai_api, or call_ollama_api.")
  }

  n_chunks <- prompt$n_chunks
  n_items  <- prompt$n_items %||% length(prompt$taxa %||% character(0))
  if (verbose) {
    message(sprintf(
      "prompt_api: submitting %d chunk(s) for %d item(s)...",
      n_chunks, n_items
    ))
  }

  results       <- vector("list", n_chunks)
  failed_chunks <- integer(0)

  for (i in seq_len(n_chunks)) {
    if (verbose) {
      message(sprintf("  Chunk %d / %d (%d item(s))...",
                      i, n_chunks, length(prompt$chunks[[i]])))
    }

    raw <- tryCatch(
      .call_api_single(prompt$prompts[[i]], llm_fn),
      error = function(e) {
        warning(sprintf(
          "prompt_api: chunk %d failed -- %s", i, conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )

    if (is.null(raw)) {
      failed_chunks <- c(failed_chunks, i)
    } else {
      results[[i]] <- raw
    }

    if (i < n_chunks) Sys.sleep(pause_seconds)
  }

  if (length(failed_chunks) > 0L) {
    warning(sprintf(
      "prompt_api: %d of %d chunk(s) failed (indices: %s). Taxa in failed chunks will have NA values. Check provider credentials and network connection.",
      length(failed_chunks), n_chunks, paste(failed_chunks, collapse = ", ")
    ), call. = FALSE)
  }

  if (all(vapply(results, is.null, logical(1)))) {
    stop("prompt_api: all chunks failed. Check provider credentials and network connection.")
  }

  out <- .combine_chunk_responses(results)
  attr(out, "failed_chunks") <- if (length(failed_chunks) > 0L) failed_chunks else NULL
  attr(out, "n_chunks") <- n_chunks
  out
}


# ==============================================================================
# STEP 2 -- PATH 3: Manual file handoff
# ==============================================================================

#' Submit a Prompt Manually via Any LLM Interface
#'
#' Writes prompt file(s) from an \code{llm_prompt} object
#' to disk and prints step-by-step instructions for manual submission to
#' any LLM web interface or desktop app (Path 3). Pauses R execution until
#' the user presses Enter, preventing the next script lines from running
#' prematurely.
#'
#' @param prompt An \code{llm_prompt} object (e.g. from
#'   \code{build_habitat_prompt()} (TaxaHabitat)).
#' @param out_dir Character. Directory to write prompt and response files.
#'   Default \code{getwd()}. Created if it does not exist.
#' @param prefix Character. Filename prefix. Default \code{"habitat"}.
#'   Files are named \code{<prefix>_prompt_1.txt},
#'   \code{<prefix>_prompt_2.txt}, etc.
#'
#' @return Invisibly returns a named list:
#'   \describe{
#'     \item{prompt_files}{Character vector of written prompt file paths.}
#'     \item{response_files}{Character vector of expected response file paths.}
#'     \item{n_chunks}{Integer. Number of chunks.}
#'     \item{taxon_list}{Character vector. All taxa submitted.}
#'   }
#'
#' @details
#' The function pauses R by calling \code{readline()} after printing
#' instructions. This is intentional -- it prevents the next line of your
#' script (typically \code{read_llm_response()}) from running before you
#' have saved the response file(s).
#'
#' @seealso \code{\link{read_llm_response}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' prompt <- TaxaHabitat::build_habitat_prompt(c("Gadus morhua", "Sebastes mystinus"))
#' info   <- prompt_manual(prompt, out_dir = "habitat_assignment")
#' # paste prompts into your LLM, save responses to the listed files
#' raw_text <- read_llm_response(info$response_files)
#' }

prompt_manual <- function(prompt,
                          out_dir = getwd(),
                          prefix  = "habitat") {

  if (!inherits(prompt, "llm_prompt")) {
    stop("prompt_manual: 'prompt' must be an llm_prompt object ",
         "(e.g. from build_habitat_prompt() or build_geo_prompt()).")
  }

  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE)
    message(sprintf("prompt_manual: created directory '%s'", out_dir))
  }

  n_chunks <- prompt$n_chunks

  prompt_files   <- file.path(out_dir,
                              sprintf("%s_prompt_%d.txt",   prefix, seq_len(n_chunks)))
  response_files <- file.path(out_dir,
                              sprintf("%s_response_%d.txt", prefix, seq_len(n_chunks)))

  for (i in seq_len(n_chunks)) {
    writeLines(prompt$prompts[[i]], con = prompt_files[i])
  }

  cat("\n")
  cat(rep("=", 70), "\n", sep = "")
  cat("  prompt_manual: prompt file(s) ready\n")
  cat(rep("=", 70), "\n\n", sep = "")

  for (i in seq_len(n_chunks)) {
    cat(sprintf("  CHUNK %d of %d (%d taxa):\n", i, n_chunks,
                length(prompt$chunks[[i]])))
    cat(sprintf("    1. Open:  %s\n", normalizePath(prompt_files[i])))
    cat(sprintf("    2. Paste the entire file contents into your LLM.\n"))
    cat(sprintf("    3. Save the response to: %s\n\n",
                normalizePath(response_files[i])))
  }

  cat("  ALTERNATIVE: paste the LLM response directly into R as a string:\n")
  cat('  raw_text <- "taxon_name,<habitat cols>,...\\n..."\n\n')
  cat("  WHEN ALL RESPONSE FILES ARE SAVED, press Enter to continue.\n")
  cat("  (R is paused -- your script will not advance until you press Enter.)\n\n")

  readline("  >> Press Enter when ready: ")

  cat("\n")
  cat(rep("=", 70), "\n", sep = "")
  cat("  Next steps -- run these lines in R:\n")
  cat(rep("=", 70), "\n\n", sep = "")
  if (n_chunks == 1L) {
    cat(sprintf("  raw_text <- read_llm_response(\"%s\")\n",
                normalizePath(response_files[1])))
  } else {
    file_vec <- paste0(
      "c(\n    \"",
      paste(normalizePath(response_files), collapse = "\",\n    \""),
      "\")"
    )
    cat(sprintf("  raw_text <- read_llm_response(%s)\n", file_vec))
  }
  cat(rep("=", 70), "\n\n", sep = "")

  invisible(list(
    prompt_files   = prompt_files,
    response_files = response_files,
    n_chunks       = n_chunks,
    taxon_list     = prompt$taxa
  ))
}


# ==============================================================================
# STEP 2 -- PATH 3 supplement: Read saved response file(s)
# ==============================================================================

#' Read Saved LLM Response File(s)
#'
#' Reads one or more plain-text LLM response files, strips duplicate CSV
#' headers from chunks 2 onward, and returns a single concatenated string
#' ready for a response parser.
#'
#' @param files Character vector. Path(s) to response file(s). Files are
#'   read and concatenated in order. For multi-chunk submissions, supply
#'   all chunk files in the same order they were submitted.
#'
#' @return A length-1 character string.
#'
#' @details
#' Missing files generate a warning (not an error) so that partial
#' results can still be parsed. If \code{taxon_name} is absent from the
#' combined text, a warning is also emitted.
#'
#' @seealso \code{\link{prompt_manual}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' raw_text <- read_llm_response("habitat_response_1.txt")
#' raw_text <- read_llm_response(c("habitat_response_1.txt",
#'                                 "habitat_response_2.txt"))
#' }

read_llm_response <- function(files) {

  if (!is.character(files) || length(files) == 0L) {
    stop("read_llm_response: 'files' must be a non-empty character vector of file paths.")
  }

  chunks <- vector("character", length(files))

  for (i in seq_along(files)) {
    f <- files[i]
    if (!file.exists(f)) {
      warning(sprintf("read_llm_response: file not found, skipping: %s", f), call. = FALSE)
      chunks[i] <- ""
      next
    }
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    if (i > 1L) {
      # Strip duplicate header row from chunks 2+
      # Header is any line containing "taxon_name" and a comma.
      lines      <- strsplit(txt, "\n")[[1]]
      header_idx <- which(grepl("taxon_name", lines, ignore.case = TRUE) &
                            grepl(",", lines, fixed = TRUE))[1]
      if (!is.na(header_idx)) lines <- lines[-header_idx]
      txt <- paste(lines, collapse = "\n")
    }
    chunks[i] <- txt
  }

  combined <- paste(chunks[nzchar(chunks)], collapse = "\n")

  if (!grepl("taxon_name", combined, ignore.case = TRUE)) {
    warning(
      "read_llm_response: 'taxon_name' column not found in the combined response. ",
      "Check that you copied the full LLM output including the header row.",
      call. = FALSE
    )
  }

  combined
}


# ==============================================================================
# Internal helpers
# ==============================================================================


#' Call llm_fn for a single prompt string (one chunk).
#' @noRd
.call_api_single <- function(prompt_str, llm_fn) {
  llm_fn(prompt_str)
}


#' Concatenate multi-chunk API responses; strip duplicate headers.
#' @noRd
.combine_chunk_responses <- function(results) {
  non_null <- Filter(Negate(is.null), results)
  if (length(non_null) == 0L) return("")  # empty string, not length-0 character
  if (length(non_null) == 1L) return(non_null[[1]])

  chunks <- character(length(non_null))
  chunks[1] <- non_null[[1]]

  for (i in seq_along(non_null)[-1]) {
    txt   <- non_null[[i]]
    lines <- strsplit(txt, "\n")[[1]]
    hdr   <- which(grepl("taxon_name", lines, ignore.case = TRUE) &
                     grepl(",", lines, fixed = TRUE))[1]
    if (!is.na(hdr)) lines <- lines[-hdr]
    chunks[i] <- paste(lines, collapse = "\n")
  }

  paste(chunks, collapse = "\n")
}


#' Null-coalescing operator
#'
#' Returns `x` if it is non-`NULL` and has length > 0; otherwise returns `y`.
#' Defined once in TaxaTools; downstream packages import via
#' `@importFrom TaxaTools %||%`.
#'
#' @param x,y Values to coalesce.
#' @return `x` when non-`NULL` and `length(x) > 0`, otherwise `y`.
#' @examples
#' NULL %||% "default"
#' # "default"
#' "value" %||% "default"
#' # "value"
#' @name null-coalesce
#' @export
`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0) x else y


# ==============================================================================
# Google Gemini API
# ==============================================================================

#' Call the Google Gemini API with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to the
#' Google Gemini generateContent API and returns the model's response as a
#' plain character string. Drop-in replacement for
#' \code{\link{call_anthropic_api}} when used as the \code{llm_fn} argument
#' to any function that accepts one.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Gemini model identifier.
#'   Default \code{"gemini-2.0-flash"} (free tier as of 2026).
#'   Other free-tier options: \code{"gemini-2.5-flash-lite"},
#'   \code{"gemini-2.5-flash"}.
#'   See \url{https://ai.google.dev/gemini-api/docs/models} for the full list.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   Sufficient for most taxonomy and habitat prompts. Increase for longer
#'   outputs (e.g., large species lists). Higher values increase API cost.
#' @param api_key Character. Google AI Studio API key. Defaults to the
#'   \code{GEMINI_API_KEY} environment variable. Get a free key at
#'   \url{https://aistudio.google.com/apikey} and add
#'   \code{GEMINI_API_KEY=AIza...} to \code{~/.Renviron}.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops on any non-200 HTTP status or safety block.
#'
#' @details
#' \strong{Free tier:} The Gemini API offers a genuinely free tier through
#' Google AI Studio with no credit card required. Rate limits apply (requests
#' per minute and per day vary by model). See
#' \url{https://ai.google.dev/gemini-api/docs/rate-limits}.
#'
#' \strong{llm_fn usage:}
#' \preformatted{
#' # Direct use
#' screen_pdf_structure(pdf_content, llm_fn = call_gemini_api)
#' prompt_api(prompt,      llm_fn = call_gemini_api)
#'
#' # Non-default model via closure
#' my_gemini <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash")
#' screen_pdf_structure(pdf_content, llm_fn = my_gemini)
#' }
#'
#' @seealso \code{\link{call_anthropic_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_ollama_api}}, \code{\link{prompt_api}}
#'
#' @importFrom httr2 request req_url_query req_headers req_body_json req_error
#'   req_perform resp_status resp_body_json
#' @export
#'
#' @examples
#' \dontrun{
#' Sys.setenv(GEMINI_API_KEY = "AIza...")
#' answer <- call_gemini_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_gemini_api <- function(prompt_str,
                            model      = "gemini-2.0-flash",
                            max_tokens = 3000L,
                            api_key    = Sys.getenv("GEMINI_API_KEY")) {

  if (!is.character(prompt_str) || length(prompt_str) != 1L) {
    stop("call_gemini_api: 'prompt_str' must be a length-1 character string.")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("call_gemini_api: package 'httr2' is required. ",
         "Install with: install.packages('httr2')")
  }
  if (!nzchar(api_key)) {
    stop(
      "call_gemini_api: no API key found.\n",
      "Get a free key at https://aistudio.google.com/apikey and set it with:\n",
      "  Sys.setenv(GEMINI_API_KEY = 'AIza...')\n",
      "or add GEMINI_API_KEY=AIza... to your ~/.Renviron"
    )
  }

  url <- sprintf(
    "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent",
    model
  )

  body <- list(
    contents         = list(list(parts = list(list(text = prompt_str)))),
    generationConfig = list(maxOutputTokens = as.integer(max_tokens))
  )

  resp <- httr2::request(url) |>
    httr2::req_url_query(key = api_key) |>
    httr2::req_headers("Content-Type" = "application/json") |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body_err <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf(
      "call_gemini_api: HTTP %d: %s",
      status,
      body_err$error$message %||% "(no message)"
    ))
  }

  parsed     <- httr2::resp_body_json(resp)
  candidates <- parsed$candidates

  if (is.null(candidates) || length(candidates) == 0L) {
    feedback <- parsed$promptFeedback$blockReason
    if (!is.null(feedback)) {
      stop(sprintf(
        "call_gemini_api: prompt blocked by Gemini safety filters: %s", feedback
      ))
    }
    stop("call_gemini_api: API response contained no candidates.")
  }

  parts <- candidates[[1]]$content$parts
  if (is.null(parts) || length(parts) == 0L) {
    stop("call_gemini_api: candidate contained no content parts.")
  }

  # Concatenate all text parts (Gemini can split a response into multiple parts)
  text_parts <- vapply(parts, function(p) p$text %||% "", character(1))
  out <- paste(text_parts, collapse = "")
  attr(out, "model") <- model
  out
}


# ==============================================================================
# OpenAI API (ChatGPT)
# ==============================================================================

#' Call the OpenAI Chat Completions API with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to the
#' OpenAI Chat Completions API and returns the model's response as a plain
#' character string. Drop-in replacement for
#' \code{\link{call_anthropic_api}} when used as the \code{llm_fn} argument
#' to any function that accepts one.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. OpenAI model identifier.
#'   Default \code{"gpt-4o-mini"} (cost-efficient capable option as of 2026).
#'   Other options: \code{"gpt-4o"}, \code{"gpt-4.1"}.
#'   See \url{https://platform.openai.com/docs/models} for the full list.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   Sufficient for most taxonomy and habitat prompts. Increase for longer
#'   outputs (e.g., large species lists). Higher values increase API cost.
#' @param api_key Character. OpenAI API key. Defaults to the
#'   \code{OPENAI_API_KEY} environment variable. Get a key at
#'   \url{https://platform.openai.com/api-keys} and add
#'   \code{OPENAI_API_KEY=sk-...} to \code{~/.Renviron}.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops on any non-200 HTTP status.
#'
#' @details
#' \strong{Pricing note:} OpenAI requires a paid account (or expiring $5 trial
#' credits for new accounts). There is no ongoing free API tier.
#' \code{gpt-4o-mini} is the most economical capable model.
#'
#' \strong{llm_fn usage:}
#' \preformatted{
#' # Direct use
#' screen_pdf_structure(pdf_content, llm_fn = call_openai_api)
#' prompt_api(prompt,      llm_fn = call_openai_api)
#'
#' # Non-default model via closure
#' my_openai <- function(p, ...) call_openai_api(p, model = "gpt-4o")
#' screen_pdf_structure(pdf_content, llm_fn = my_openai)
#' }
#'
#' @seealso \code{\link{call_anthropic_api}}, \code{\link{call_gemini_api}},
#'   \code{\link{call_ollama_api}}, \code{\link{prompt_api}}
#'
#' @importFrom httr2 request req_headers req_body_json req_error req_perform
#'   resp_status resp_body_json
#' @export
#'
#' @examples
#' \dontrun{
#' Sys.setenv(OPENAI_API_KEY = "sk-...")
#' answer <- call_openai_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_openai_api <- function(prompt_str,
                            model      = "gpt-4o-mini",
                            max_tokens = 3000L,
                            api_key    = Sys.getenv("OPENAI_API_KEY")) {

  if (!is.character(prompt_str) || length(prompt_str) != 1L) {
    stop("call_openai_api: 'prompt_str' must be a length-1 character string.")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("call_openai_api: package 'httr2' is required. ",
         "Install with: install.packages('httr2')")
  }
  if (!nzchar(api_key)) {
    stop(
      "call_openai_api: no API key found.\n",
      "Get a key at https://platform.openai.com/api-keys and set it with:\n",
      "  Sys.setenv(OPENAI_API_KEY = 'sk-...')\n",
      "or add OPENAI_API_KEY=sk-... to your ~/.Renviron"
    )
  }

  body <- list(
    model      = model,
    max_tokens = as.integer(max_tokens),
    messages   = list(list(role = "user", content = prompt_str))
  )

  resp <- httr2::request("https://api.openai.com/v1/chat/completions") |>
    httr2::req_headers(
      "Authorization" = paste("Bearer", api_key),
      "Content-Type"  = "application/json"
    ) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body_err <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf(
      "call_openai_api: HTTP %d: %s",
      status,
      body_err$error$message %||% "(no message)"
    ))
  }

  parsed  <- httr2::resp_body_json(resp)
  choices <- parsed$choices

  if (is.null(choices) || length(choices) == 0L) {
    stop("call_openai_api: API response contained no choices.")
  }

  content <- choices[[1]]$message$content
  if (is.null(content) || !nzchar(trimws(content))) {
    finish_reason <- choices[[1]]$finish_reason %||% "unknown"
    stop(sprintf(
      "call_openai_api: response content is empty (finish_reason: %s).",
      finish_reason
    ))
  }

  attr(content, "model") <- model
  content
}


# ==============================================================================
# Ollama (local models — no API key required)
# ==============================================================================

#' Call a Local Ollama Model with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to a locally
#' running Ollama instance and returns the model's response as a plain
#' character string. Drop-in replacement for
#' \code{\link{call_anthropic_api}} when used as the \code{llm_fn} argument
#' to any function that accepts one. Completely free — no API key
#' or internet connection required after model download.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Ollama model name as listed by \code{ollama list}
#'   in Terminal. Default \code{"llama3.2"}.
#'   Pull a model before first use: \code{ollama pull llama3.2}.
#'   Browse available models at \url{https://ollama.com/library}.
#'   Capable options for Apple Silicon: \code{"llama3.1:8b"},
#'   \code{"mistral"}, \code{"gemma3:12b"}, \code{"qwen2.5:14b"}.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   Sufficient for most taxonomy and habitat prompts. Increase for longer
#'   outputs (e.g., large species lists). Higher values increase API cost.
#'   Note: behaviour is model-dependent; some models may ignore this setting.
#' @param base_url Character. Base URL of the Ollama server.
#'   Default \code{"http://localhost:11434"}. Change only if running Ollama
#'   on a different host or port.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops with a clear message if Ollama is not running or the model has
#'   not been pulled.
#'
#' @details
#' \strong{One-time setup:}
#' \enumerate{
#'   \item Install Ollama from \url{https://ollama.com}
#'   \item In Terminal: \code{ollama pull llama3.2}
#'   \item Confirm with: \code{ollama list}
#' }
#' Ollama starts automatically on macOS after installation; no manual server
#' start is needed.
#'
#' \strong{Performance on Apple Silicon:} 7B-14B parameter models run well
#' via Metal GPU acceleration on arm64 Macs. Larger models require more RAM.
#' Expect slower throughput than cloud APIs for equivalent capability.
#'
#' \strong{llm_fn usage:}
#' \preformatted{
#' # Direct use (default model)
#' screen_pdf_structure(pdf_content, llm_fn = call_ollama_api)
#' prompt_api(prompt,      llm_fn = call_ollama_api)
#'
#' # Specific model via closure
#' my_ollama <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b")
#' screen_pdf_structure(pdf_content, llm_fn = my_ollama)
#' }
#'
#' @seealso \code{\link{call_anthropic_api}}, \code{\link{call_gemini_api}},
#'   \code{\link{call_openai_api}}, \code{\link{prompt_api}}
#'
#' @importFrom httr2 request req_headers req_body_json req_error req_perform
#'   resp_status resp_body_json
#' @export
#'
#' @examples
#' \dontrun{
#' # Ollama must be running and model pulled first:
#' # In Terminal: ollama pull llama3.2
#' answer <- call_ollama_api("What phylum do sea urchins belong to?")
#' cat(answer)
#'
#' # Larger model (requires more RAM):
#' answer <- call_ollama_api("What phylum do sea urchins belong to?",
#'                           model = "qwen2.5:14b")
#' }

call_ollama_api <- function(prompt_str,
                            model      = "llama3.2",
                            max_tokens = 3000L,
                            base_url   = "http://localhost:11434") {

  if (!is.character(prompt_str) || length(prompt_str) != 1L) {
    stop("call_ollama_api: 'prompt_str' must be a length-1 character string.")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("call_ollama_api: package 'httr2' is required. ",
         "Install with: install.packages('httr2')")
  }

  url  <- paste0(gsub("/$", "", base_url), "/api/chat")
  body <- list(
    model    = model,
    stream   = FALSE,
    messages = list(list(role = "user", content = prompt_str)),
    options  = list(num_predict = as.integer(max_tokens))
  )

  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_headers("Content-Type" = "application/json") |>
      httr2::req_body_json(body) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) {
      stop(
        "call_ollama_api: could not connect to Ollama at ", base_url, ".\n",
        "Make sure Ollama is installed and running (https://ollama.com).\n",
        "Original error: ", conditionMessage(e),
        call. = FALSE
      )
    }
  )

  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body_err <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    err_msg  <- body_err$error %||% "(no message)"
    if (status == 404L ||
        grepl("model.*not found|not found.*model|pull|does not exist|unknown model",
              err_msg, ignore.case = TRUE)) {
      stop(sprintf(
        "call_ollama_api: model '%s' not found locally.\nPull it first: ollama pull %s",
        model, model
      ))
    }
    stop(sprintf("call_ollama_api: HTTP %d: %s", status, err_msg))
  }

  parsed  <- httr2::resp_body_json(resp)
  content <- parsed$message$content

  if (is.null(content) || !nzchar(trimws(content))) {
    done_reason <- parsed$done_reason %||% "unknown"
    stop(sprintf(
      "call_ollama_api: response content is empty (done_reason: %s).",
      done_reason
    ))
  }

  attr(content, "model") <- model
  content
}
