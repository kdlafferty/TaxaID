# ==============================================================================
# llm_api_utils.R
# TaxaTools — LLM provider utilities
#
# Exported functions:
#   call_anthropic_api()    Provider: Anthropic — thin wrapper around call_api()
#   call_gemini_api()       Provider: Google Gemini — thin wrapper around call_api()
#   call_openai_api()       Provider: OpenAI/compat — thin wrapper around call_api()
#   call_azure_api()        Provider: Azure OpenAI (DOI) — thin wrapper around call_api()
#   call_ollama_api()       Provider: Ollama (local) — thin wrapper around call_api()
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
# Note: the five provider call_*_api() functions are thin wrappers around
#   call_api() (R/call_api.R), which owns all HTTP logic via registry-based
#   dispatch (inst/model_tiers.json). Wrappers are kept for backward
#   compatibility and for use as llm_fn arguments.
#
# Provider API keys (set in ~/.Renviron):
#   ANTHROPIC_API_KEY       — required for call_anthropic_api() (no free tier)
#   GEMINI_API_KEY          — required for call_gemini_api() (free tier available)
#   OPENAI_API_KEY          — required for call_openai_api() (no ongoing free tier)
#   (none)                  — call_ollama_api() needs no key; runs models locally
#   AZURE_OPENAI_API_KEY    — required for call_azure_api() (DOI employees only;
#                             requires connection to a DOI computer system or DOI VPN)
# ==============================================================================


# ==============================================================================
# Anthropic — thin wrapper around call_api()
# ==============================================================================

#' Call the Anthropic API with a Single Prompt String
#'
#' Low-level generic function: submits one plain character string to the
#' Anthropic Messages API and returns the model's response as a plain
#' character string. No chunking, no S3 class requirements, no
#' domain-specific logic. Thin wrapper around \code{\link{call_api}}.
#'
#' Use this directly when you have already built your own prompt string
#' (e.g. for geographic screening, PDF extraction, or any ad-hoc task).
#' For habitat assignment with a \code{build_habitat_prompt()} (TaxaHabitat) object,
#' use \code{\link{prompt_api}} instead -- it handles chunking and
#' per-chunk retries automatically.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Exact Anthropic model identifier, e.g.
#'   \code{"claude-sonnet-4-6"}. Default \code{NULL} resolves to the latest
#'   model for \code{tier} via \code{\link{list_models}}. Specify an exact
#'   model to pin a version for reproducibility.
#' @param tier Character. Capability tier used when \code{model = NULL}:
#'   \code{"fast"} (cheapest), \code{"mid"} (balanced, default), or
#'   \code{"top"} (most capable). Ignored when \code{model} is specified.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   Sufficient for most taxonomy and habitat prompts. Increase for longer
#'   outputs (e.g., large species lists). Higher values increase API cost.
#' @param api_key Character. Anthropic API key. Defaults to the
#'   \code{ANTHROPIC_API_KEY} environment variable.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops on any non-200 HTTP status.
#'
#' @seealso \code{\link{call_api}} for the generic dispatcher.
#'   \code{\link{prompt_api}} for multi-chunk \code{llm_prompt} submission.
#'   \code{\link{call_gemini_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_ollama_api}}, \code{\link{call_azure_api}} for
#'   alternative providers.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-...")
#' answer <- call_anthropic_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_anthropic_api <- function(prompt_str,
                               model      = NULL,
                               tier       = c("mid", "fast", "top"),
                               max_tokens = 3000L,
                               api_key    = Sys.getenv("ANTHROPIC_API_KEY")) {
  tier <- match.arg(tier)
  call_api(prompt_str,
           provider   = "anthropic",
           tier       = tier,
           model      = model,
           max_tokens = max_tokens,
           api_key    = if (nzchar(api_key)) api_key else NULL)
}


# ==============================================================================
# STEP 2 -- PATH 1: Multi-chunk llm_prompt dispatcher (provider-neutral)
# ==============================================================================

#' Submit a Multi-Chunk LLM Prompt to Any Provider
#'
#' Submits an \code{llm_prompt} object to an LLM provider,
#' handling multi-chunk prompts automatically. Provider is selected via the
#' \code{llm_fn} argument, which defaults to \code{\link{call_api}}
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
#'   Default: \code{\link{call_api}} (uses \code{options("TaxaID.provider")}).
#'   Built-in alternatives: \code{\link{call_anthropic_api}},
#'   \code{\link{call_gemini_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_ollama_api}}.
#'   To use a non-default model or API key, pass a closure:
#'   \preformatted{
#'   my_gemini <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash-lite")
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
#'     directly to provider functions (\code{call_api()}, \code{call_anthropic_api()}, etc.)
#'     or to \code{draft_methods_text()} / \code{draft_results_text()}.
#' }
#' \code{prompt_api()} requires the S3 object; the individual provider
#' functions accept plain strings.
#'
#' \strong{Provider selection:} All provider-specific concerns (API keys,
#' model names, token limits) belong inside the \code{llm_fn} function.
#' Use a closure to fix non-default parameters for any provider:
#' \preformatted{
#' # Specific provider and tier via call_api
#' my_fn <- function(p, ...) call_api(p, provider = "gemini", tier = "fast")
#'
#' # Anthropic with a non-default model
#' my_fn <- function(p, ...) call_anthropic_api(p, model = "claude-haiku-4-5-20251001")
#'
#' # Local Ollama model
#' my_fn <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b")
#'
#' raw_text <- prompt_api(prompt, llm_fn = my_fn)
#' }
#'
#' @seealso \code{\link{call_api}}, \code{\link{call_anthropic_api}},
#'   \code{\link{call_gemini_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_ollama_api}}, \code{\link{call_azure_api}},
#'   \code{\link{prompt_manual}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # With TaxaHabitat
#' prompt <- TaxaHabitat::build_habitat_prompt(c("Gadus morhua", "Sebastes mystinus"))
#'
#' # Auto-detected provider (default)
#' raw_text <- prompt_api(prompt)
#'
#' # Gemini free tier
#' raw_text <- prompt_api(prompt, llm_fn = call_gemini_api)
#'
#' # Local Ollama
#' raw_text <- prompt_api(prompt, llm_fn = call_ollama_api)
#'
#' # Azure OpenAI (DOI employees; requires DOI network or VPN)
#' raw_text <- prompt_api(prompt, llm_fn = call_azure_api)
#' }

prompt_api <- function(prompt,
                       llm_fn        = getOption("TaxaID.llm_fn", call_api),
                       pause_seconds = 1,
                       verbose       = TRUE) {

  if (!inherits(prompt, "llm_prompt")) {
    stop("prompt_api: 'prompt' must be an llm_prompt object ",
         "(e.g. from build_habitat_prompt() or build_geo_prompt()).")
  }
  if (!is.function(llm_fn)) {
    stop("prompt_api: 'llm_fn' must be a function with signature ",
         "function(prompt_str, ...) -> character(1). ",
         "Use call_api, call_anthropic_api, call_gemini_api, call_openai_api, or call_ollama_api.")
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
# Google Gemini API — thin wrapper around call_api()
# ==============================================================================

#' Call the Google Gemini API with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to the
#' Google Gemini generateContent API and returns the model's response as a
#' plain character string. Drop-in replacement for
#' \code{\link{call_api}} when used as the \code{llm_fn} argument
#' to any function that accepts one. Thin wrapper around \code{\link{call_api}}.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Exact Gemini model identifier, e.g.
#'   \code{"gemini-2.5-flash"}. Default \code{NULL} resolves to the latest
#'   model for \code{tier} via \code{\link{list_models}}. Specify an exact
#'   model to pin a version for reproducibility.
#' @param tier Character. Capability tier used when \code{model = NULL}:
#'   \code{"fast"} (cheapest), \code{"mid"} (balanced, default), or
#'   \code{"top"} (most capable). Ignored when \code{model} is specified.
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
#' @seealso \code{\link{call_api}}, \code{\link{call_anthropic_api}},
#'   \code{\link{call_openai_api}}, \code{\link{call_ollama_api}},
#'   \code{\link{call_azure_api}}, \code{\link{prompt_api}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' Sys.setenv(GEMINI_API_KEY = "AIza...")
#' answer <- call_gemini_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_gemini_api <- function(prompt_str,
                            model      = NULL,
                            tier       = c("mid", "fast", "top"),
                            max_tokens = 3000L,
                            api_key    = Sys.getenv("GEMINI_API_KEY")) {
  tier <- match.arg(tier)
  call_api(prompt_str,
           provider   = "gemini",
           tier       = tier,
           model      = model,
           max_tokens = max_tokens,
           api_key    = if (nzchar(api_key)) api_key else NULL)
}


# ==============================================================================
# OpenAI API (ChatGPT) — thin wrapper around call_api()
# ==============================================================================

#' Call the OpenAI Chat Completions API with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to the
#' OpenAI Chat Completions API and returns the model's response as a plain
#' character string. Drop-in replacement for \code{\link{call_api}} when
#' used as the \code{llm_fn} argument to any function that accepts one.
#' Thin wrapper around \code{\link{call_api}}.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Exact OpenAI model identifier, e.g.
#'   \code{"gpt-4o-mini"}. Default \code{NULL} resolves to the latest model
#'   for \code{tier} via \code{\link{list_models}}. Specify an exact model to
#'   pin a version for reproducibility.
#' @param tier Character. Capability tier used when \code{model = NULL}:
#'   \code{"fast"} (cheapest), \code{"mid"} (balanced, default), or
#'   \code{"top"} (most capable). Ignored when \code{model} is specified.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   Sufficient for most taxonomy and habitat prompts. Increase for longer
#'   outputs (e.g., large species lists). Higher values increase API cost.
#' @param base_url Character. Base URL of the API endpoint. Default
#'   \code{"https://api.openai.com"} (OpenAI). Any OpenAI-compatible API can
#'   be used by changing this URL -- see Details. When using a non-default
#'   URL, register the provider with \code{\link{register_provider}} to enable
#'   automatic tier resolution, or specify \code{model} explicitly.
#' @param api_key Character. API key for the provider. Defaults to the
#'   \code{OPENAI_API_KEY} environment variable for the standard OpenAI
#'   endpoint. For alternative providers, pass the key directly or via
#'   \code{Sys.getenv("MY_KEY_VAR")} in a closure.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops on any non-200 HTTP status.
#'
#' @details
#' \strong{Pricing note:} OpenAI requires a paid account (or expiring $5 trial
#' credits for new accounts). There is no ongoing free API tier.
#' \code{gpt-4o-mini} is the most economical capable model.
#'
#' \strong{OpenAI-compatible providers:}
#' Many providers implement the OpenAI Chat Completions API. Use \code{base_url}
#' to reach them with a single function, or use \code{\link{register_provider}}
#' for automatic tier resolution:
#' \preformatted{
#' # xAI Grok -- specify model explicitly
#' Sys.setenv(XAI_API_KEY = "xai-...")
#' my_grok <- function(p, ...) call_openai_api(p,
#'   model    = "grok-3-mini",
#'   base_url = "https://api.x.ai",
#'   api_key  = Sys.getenv("XAI_API_KEY")
#' )
#' options(TaxaID.llm_fn = my_grok)
#'
#' # Or register for automatic tier resolution:
#' register_provider("xai", "XAI_API_KEY", "https://api.x.ai",
#'   fallback_models = list(fast = "grok-3-mini", mid = "grok-3", top = "grok-3")
#' )
#' }
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
#' @seealso \code{\link{call_api}}, \code{\link{call_anthropic_api}},
#'   \code{\link{call_gemini_api}}, \code{\link{call_ollama_api}},
#'   \code{\link{call_azure_api}}, \code{\link{prompt_api}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' Sys.setenv(OPENAI_API_KEY = "sk-...")
#' answer <- call_openai_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_openai_api <- function(prompt_str,
                            model      = NULL,
                            tier       = c("mid", "fast", "top"),
                            max_tokens = 3000L,
                            base_url   = "https://api.openai.com",
                            api_key    = Sys.getenv("OPENAI_API_KEY")) {

  tier       <- match.arg(tier)
  base_clean <- gsub("/$", "", base_url)

  # Standard OpenAI endpoint: route directly
  if (grepl("api\\.openai\\.com", base_clean, fixed = FALSE)) {
    return(call_api(prompt_str,
                    provider   = "openai",
                    tier       = tier,
                    model      = model,
                    max_tokens = max_tokens,
                    api_key    = if (nzchar(api_key)) api_key else NULL))
  }

  # Custom base_url: check if a registered provider matches
  reg <- .get_registry()
  for (prov in names(reg$providers)) {
    prov_base <- gsub("/$", "", reg$providers[[prov]]$base_url %||% "")
    if (nzchar(prov_base) && identical(base_clean, prov_base)) {
      return(call_api(prompt_str,
                      provider   = prov,
                      tier       = tier,
                      model      = model,
                      max_tokens = max_tokens,
                      api_key    = if (nzchar(api_key)) api_key else NULL))
    }
  }

  # Unknown provider: model must be explicit
  if (is.null(model)) {
    stop(paste0(
      "call_openai_api: 'model' must be specified when using a custom base_url.\n",
      "Register the provider with register_provider() to enable tier resolution,\n",
      "or pass model explicitly: call_openai_api(p, model = 'model-name', ",
      "base_url = '", base_url, "')"
    ))
  }
  # Route through openai with base_url override (uses bearer auth)
  call_api(prompt_str,
           provider   = "openai",
           tier       = tier,
           model      = model,
           max_tokens = max_tokens,
           api_key    = if (nzchar(api_key)) api_key else NULL,
           base_url   = base_clean)
}


# ==============================================================================
# Azure OpenAI API (U.S. Department of the Interior employees only)
# — thin wrapper around call_api()
# ==============================================================================

#' Call the Azure OpenAI API with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to an
#' Azure OpenAI Chat Completions endpoint and returns the model's response
#' as a plain character string. Drop-in replacement for
#' \code{\link{call_api}} when used as the \code{llm_fn} argument to any
#' function that accepts one. Thin wrapper around \code{\link{call_api}}.
#'
#' @section Department of the Interior (DOI) employees only:
#' The default endpoint (\code{api-dev.ai.doi.net}) is an internal DOI
#' service. \strong{Access requires an active connection to a DOI computer
#' system or the DOI VPN.} Calls from outside the DOI network will fail with
#' a connection error. The \code{AZURE_OPENAI_API_KEY} must be obtained
#' through DOI IT channels.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param model Character. Azure deployment name, e.g. \code{"gpt-5.1"}.
#'   Default \code{NULL} resolves to the latest available deployment for
#'   \code{tier} via \code{\link{list_models}}. Specify an exact name to
#'   pin for reproducibility.
#' @param tier Character. Capability tier used when \code{model = NULL}:
#'   \code{"fast"}, \code{"mid"} (default), or \code{"top"}. For Azure, all
#'   tiers currently map to the same DOI deployment; the param is accepted for
#'   interface consistency.
#' @param endpoint Character. Full deployment URL override (backward-compatible
#'   escape hatch). When provided, the deployment name is extracted from the
#'   URL path and the host is used to override the default DOI endpoint.
#'   Default \code{NULL} builds the URL from the registry template and the
#'   resolved \code{model} name.
#' @param max_completion_tokens Integer. Maximum tokens in the response
#'   (default 3000). Azure o-series models use this field name instead of
#'   \code{max_tokens}; handled automatically via the registry.
#' @param api_key Character. Azure OpenAI API key. Defaults to the
#'   \code{AZURE_OPENAI_API_KEY} environment variable.
#'
#' @return A length-1 character string containing the model's response text.
#'   Stops on any non-200 HTTP status.
#'
#' @details
#' \strong{llm_fn usage:}
#' \preformatted{
#' # Direct use (default DOI endpoint)
#' screen_pdf_structure(pdf_content, llm_fn = call_azure_api)
#' prompt_api(prompt,      llm_fn = call_azure_api)
#'
#' # Non-default endpoint via closure
#' my_azure <- function(p, ...) call_azure_api(p, endpoint = "https://...")
#' prompt_api(prompt, llm_fn = my_azure)
#' }
#'
#' @seealso \code{\link{call_api}}, \code{\link{call_anthropic_api}},
#'   \code{\link{call_gemini_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_ollama_api}}, \code{\link{prompt_api}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Requires DOI network or DOI VPN connection
#' Sys.setenv(AZURE_OPENAI_API_KEY = "...")
#' answer <- call_azure_api("What phylum do sea urchins belong to?")
#' cat(answer)
#' }

call_azure_api <- function(
    prompt_str,
    model                 = NULL,
    tier                  = c("mid", "fast", "top"),
    endpoint              = NULL,
    max_completion_tokens = 3000L,
    api_key               = Sys.getenv("AZURE_OPENAI_API_KEY")
) {
  tier <- match.arg(tier)

  base_url_arg <- NULL
  if (!is.null(endpoint)) {
    # Backward-compat: extract deployment name and host from full URL.
    # The host is passed as base_url so call_api swaps it into the template.
    model        <- model %||% sub(".*/deployments/([^/?]+).*", "\\1", endpoint)
    base_url_arg <- sub("^(https?://[^/]+).*", "\\1", endpoint)
  }

  call_api(prompt_str,
           provider   = "azure",
           tier       = tier,
           model      = model,
           max_tokens = as.integer(max_completion_tokens),
           api_key    = if (nzchar(api_key)) api_key else NULL,
           base_url   = base_url_arg)
}


# ==============================================================================
# Ollama (local models — no API key required) — thin wrapper around call_api()
# ==============================================================================

#' Call a Local Ollama Model with a Single Prompt String
#'
#' Low-level provider function: submits one plain character string to a locally
#' running Ollama instance and returns the model's response as a plain
#' character string. Drop-in replacement for \code{\link{call_api}} when used
#' as the \code{llm_fn} argument to any function that accepts one. Completely
#' free -- no API key or internet connection required after model download.
#' Thin wrapper around \code{\link{call_api}}.
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
#'   Behaviour is model-dependent; some models may ignore this setting.
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
#' Ollama starts automatically on macOS after installation.
#'
#' \strong{Output quality:} Local open-weight models vary substantially in
#' their ability to produce the structured JSON and CSV output that TaxaID
#' functions expect. Results are less reliable than cloud providers, especially
#' for obscure taxa. Recommended minimum for TaxaID tasks: \code{qwen2.5:14b}.
#' A warning is emitted automatically.
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
#' @seealso \code{\link{call_api}}, \code{\link{call_anthropic_api}},
#'   \code{\link{call_gemini_api}}, \code{\link{call_openai_api}},
#'   \code{\link{call_azure_api}}, \code{\link{prompt_api}}
#'
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
  call_api(prompt_str,
           provider   = "ollama",
           model      = model,
           max_tokens = max_tokens,
           base_url   = base_url)
}
