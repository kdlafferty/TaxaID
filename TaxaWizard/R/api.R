#' @importFrom httr2 request req_body_json req_headers req_perform req_error req_timeout resp_body_json resp_status
#' @importFrom jsonlite fromJSON toJSON
NULL

#' Call LLM API with Conversation History
#'
#' Low-level wrapper around httr2 that sends the conversation history
#' and system prompt to the LLM API and returns the parsed JSON response.
#' When \code{llm_fn} is supplied it is called instead of the built-in
#' Anthropic HTTP logic, allowing any provider (Azure, OpenAI, Gemini, …).
#'
#' @param messages List of message objects (role + content).
#' @param system_prompt Character. The system prompt enforcing JSON schema.
#' @param model Character. Model ID. Default \code{"claude-opus-4-6"}.
#' @param api_key Character or NULL. Anthropic API key. Default reads
#'   \code{ANTHROPIC_API_KEY} from environment. Ignored when \code{llm_fn}
#'   is supplied.
#' @param max_tokens Integer. Maximum response tokens. Default 16384.
#' @param llm_fn Function or NULL. Custom LLM caller. When non-NULL, called as
#'   \code{llm_fn(messages, system_prompt, model, max_tokens)} and must return
#'   a character string containing the raw LLM response (plain text or JSON).
#'   \code{messages} is a list of \code{list(role, content)} objects;
#'   \code{system_prompt} is a single character string.
#'
#' @return Parsed list from the LLM's JSON response.
#' @noRd
.call_llm <- function(messages,
                      system_prompt,
                      model      = "claude-opus-4-6",
                      api_key    = NULL,
                      max_tokens = 16384L,
                      llm_fn     = NULL) {

  # --- Auto-detect TaxaTools provider when no explicit llm_fn or api_key ---
  # If TaxaID.provider is set (by TaxaTools or TaxaWizard's .onAttach) and the
  # provider is not Anthropic, build a bridge so workflow_create() works on
  # non-Anthropic machines without any manual llm_fn= argument.
  if (is.null(llm_fn) && is.null(api_key)) {
    opt_provider <- getOption("TaxaID.provider")
    opt_fn       <- getOption("TaxaID.llm_fn")
    # Fall back to TaxaTools::call_api directly if llm_fn option not yet set
    if (is.null(opt_fn) && !is.null(opt_provider) &&
        requireNamespace("TaxaTools", quietly = TRUE)) {
      opt_fn <- TaxaTools::call_api
    }
    if (!is.null(opt_provider) && !identical(opt_provider, "anthropic") &&
        is.function(opt_fn)) {
      # Flatten system_prompt + conversation into one prompt string.
      # call_api() (TaxaTools) takes a single prompt_str; the full context
      # is preserved so the model sees all prior turns.
      llm_fn <- function(messages, system_prompt, model, max_tokens) {
        history_text <- paste(
          vapply(messages, function(m) {
            role <- if (identical(m$role, "user")) "User" else "Assistant"
            paste0(role, ": ", m$content)
          }, character(1L)),
          collapse = "\n\n"
        )
        combined <- paste0(system_prompt, "\n\n---\n\n", history_text)
        opt_fn(combined, max_tokens = max_tokens)
      }
    }
  }

  # --- Custom provider path ---
  if (!is.null(llm_fn)) {
    raw_text <- llm_fn(
      messages      = messages,
      system_prompt = system_prompt,
      model         = model,
      max_tokens    = max_tokens
    )
    if (!is.character(raw_text) || length(raw_text) != 1L) {
      stop(
        "llm_fn must return a single character string. Got: ",
        paste(class(raw_text), collapse = "/"),
        call. = FALSE
      )
    }
    return(.parse_engine_response(raw_text))
  }

  # --- Built-in Anthropic path ---
  api_key <- api_key %||% Sys.getenv("ANTHROPIC_API_KEY", unset = "")
  if (!nzchar(api_key)) {
    stop(
      ".call_llm: no LLM provider available for TaxaWizard.\n",
      "Options:\n",
      "  1. Set ANTHROPIC_API_KEY in ~/.Renviron\n",
      "  2. Load TaxaTools first: library(TaxaTools)  ",
      "(auto-detects Azure, Gemini, OpenAI)\n",
      "  3. Pass llm_fn= explicitly to workflow_create()",
      call. = FALSE
    )
  }

  body <- list(
    model      = model,
    max_tokens = max_tokens,
    system     = system_prompt,
    messages   = messages
  )

  resp <- tryCatch(
    httr2::request("https://api.anthropic.com/v1/messages") |>
      httr2::req_headers(
        `x-api-key`         = api_key,
        `anthropic-version`  = "2023-06-01",
        `content-type`       = "application/json"
      ) |>
      httr2::req_body_json(body, auto_unbox = TRUE) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_timeout(120) |>
      httr2::req_perform(),
    error = function(e) {
      stop("API request failed: ", conditionMessage(e), call. = FALSE)
    }
  )

  # Check for HTTP errors and report the API's error message
  status <- httr2::resp_status(resp)
  if (status >= 400L) {
    err_body <- tryCatch(
      httr2::resp_body_json(resp),
      error = function(e) list(error = list(message = "Unknown error"))
    )
    err_msg <- err_body$error$message %||% paste("HTTP", status)
    stop("Anthropic API error (", status, "): ", err_msg, call. = FALSE)
  }

  resp_body <- httr2::resp_body_json(resp)

  # Extract text content from Anthropic response
  raw_text <- resp_body$content[[1]]$text

  # Check for truncation (stop_reason == "max_tokens")
  if (identical(resp_body$stop_reason, "max_tokens")) {
    warning(
      "LLM response was truncated (hit max_tokens = ", max_tokens, "). ",
      "The workflow may be incomplete.",
      call. = FALSE
    )
  }

  # Parse the JSON from the LLM response
  .parse_engine_response(raw_text)
}


#' Parse Engine JSON Response
#'
#' Extracts and validates the JSON object from the LLM's text response.
#' Handles markdown code fences and whitespace.
#'
#' @param raw_text Character. Raw text from the LLM.
#' @return Parsed list matching the engine response schema.
#' @noRd
.parse_engine_response <- function(raw_text) {

  # Strategy: try multiple approaches to extract JSON from the response

  cleaned <- trimws(raw_text)

  # Approach 1: Strip markdown code fences
  if (grepl("```", cleaned)) {
    fenced <- sub("(?s).*```(?:json)?\\s*", "", cleaned, perl = TRUE)
    fenced <- sub("(?s)\\s*```.*", "", fenced, perl = TRUE)
    fenced <- trimws(fenced)
    result <- tryCatch(jsonlite::fromJSON(fenced, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(result)) return(result)
  }

 # Approach 2: Try parsing as-is (already valid JSON)
  result <- tryCatch(jsonlite::fromJSON(cleaned, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.null(result)) return(result)

  # Approach 3: Find all top-level {...} blocks and try each
  # Work backwards from the last } to find the main JSON object
  # (LLMs sometimes emit thinking text before the JSON)
  chars <- strsplit(cleaned, "")[[1]]
  n <- length(chars)

  # Find all positions where a top-level { starts
  brace_starts <- integer(0)
  depth <- 0L
  for (i in seq_len(n)) {
    if (chars[i] == "{") {
      if (depth == 0L) brace_starts <- c(brace_starts, i)
      depth <- depth + 1L
    } else if (chars[i] == "}") {
      depth <- depth - 1L
    }
  }

  # Try each top-level block, starting from the LAST (most likely to be the JSON)
  for (start in rev(brace_starts)) {
    depth <- 0L
    end <- NA_integer_
    for (i in seq(start, n)) {
      if (chars[i] == "{") depth <- depth + 1L
      else if (chars[i] == "}") {
        depth <- depth - 1L
        if (depth == 0L) { end <- i; break }
      }
    }
    if (!is.na(end)) {
      json_str <- substr(cleaned, start, end)
      result <- tryCatch(
        jsonlite::fromJSON(json_str, simplifyVector = FALSE),
        error = function(e) NULL
      )
      if (!is.null(result) && !is.null(result$status)) return(result)
    }
  }

  # All approaches failed — wrap plain text in a default response
  # This keeps the conversation flowing instead of crashing
  warning(
    "LLM returned plain text instead of JSON. Wrapping as incomplete response.",
    call. = FALSE
  )
  list(
    status  = "incomplete",
    phase   = "parameterize",
    message = trimws(raw_text)
  )
}


#' Null-coalescing operator
#' @noRd
`%||%` <- function(a, b) if (!is.null(a)) a else b
