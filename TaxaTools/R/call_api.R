# ==============================================================================
# call_api.R
# TaxaTools -- Generic LLM provider dispatch
#
# Design principles:
#   - One exported function (call_api) handles all providers.
#   - Provider-specific differences (endpoints, auth, body/response format)
#     are driven by data in inst/model_tiers.json, not by branching code.
#   - Three handler families cover all current providers:
#       "anthropic"    -- Anthropic Messages API
#       "gemini"       -- Google Gemini generateContent API
#       "openai_compat"-- OpenAI Chat Completions format; used by OpenAI,
#                         Azure OpenAI, Ollama, and registered custom providers
#   - New providers: add an entry to model_tiers.json (or use register_provider())
#     with handler_family, chat_endpoint/template, auth_type, and tier_patterns.
#     No R code changes needed for OpenAI-compatible providers.
#
# Exported:
#   call_api()
#
# Internal utilities (@noRd):
#   .resolve_provider()            NULL -> options(TaxaID.provider) -> error
#   .resolve_api_key()             NULL/empty -> registry env var -> error
#   .build_endpoint_url()          Resolves chat URL from registry + model + base_url
#
# Internal request builders (@noRd):
#   .build_anthropic_request()     Anthropic Messages API request
#   .build_gemini_request()        Gemini generateContent request
#   .build_openai_compat_request() OpenAI-compatible chat completions request
#
# Internal response parsers (@noRd):
#   .parse_anthropic_response()    returns list(text, tokens)
#   .parse_gemini_response()       returns list(text, tokens)
#   .parse_openai_compat_response() returns list(text, tokens)
# ==============================================================================


# ==============================================================================
# Internal utilities
# ==============================================================================

#' Resolve provider from argument or session option.
#' Errors with a setup message when no provider is configured.
#' @noRd
.resolve_provider <- function(provider) {
  if (!is.null(provider) && nzchar(provider)) return(provider)

  opt <- getOption("TaxaID.provider")
  if (!is.null(opt) && nzchar(opt)) return(opt)

  stop(paste0(
    "call_api: no LLM provider configured.\n",
    "Add an API key to ~/.Renviron and restart R, or specify a provider:\n",
    "  call_api(prompt, provider = 'anthropic')  # or 'gemini', 'openai', 'azure'\n",
    "  call_api(prompt, provider = 'ollama')      # local models, no key needed\n",
    "  register_provider() for third-party OpenAI-compatible APIs\n\n",
    "Supported providers and required environment variables:\n",
    "  Anthropic  -- ANTHROPIC_API_KEY  (https://console.anthropic.com/)\n",
    "  Gemini     -- GEMINI_API_KEY     (https://aistudio.google.com/apikey, free tier)\n",
    "  OpenAI     -- OPENAI_API_KEY     (https://platform.openai.com/api-keys)\n",
    "  Azure      -- AZURE_OPENAI_API_KEY (DOI employees only; DOI network/VPN required)\n",
    "  Ollama     -- no key required    (https://ollama.com, local)"
  ), call. = FALSE)
}


#' Resolve API key: explicit argument first, then registry env var.
#' Returns empty string for keyless providers (Ollama).
#' @noRd
.resolve_api_key <- function(provider, api_key, registry) {
  # Explicit non-empty key always wins
  if (!is.null(api_key) && nzchar(api_key)) return(api_key)

  prov_reg <- registry$providers[[provider]]

  # Keyless providers (auth_type = "none")
  if (identical(prov_reg$auth_type %||% "bearer", "none")) return("")

  # Look up env var name: registry field first, then built-in fallbacks
  key_var <- prov_reg$api_key_var %||% switch(provider,
    anthropic = "ANTHROPIC_API_KEY",
    gemini    = "GEMINI_API_KEY",
    openai    = "OPENAI_API_KEY",
    azure     = "AZURE_OPENAI_API_KEY",
    ""
  )

  if (!nzchar(key_var)) return("")  # no key variable -- treat as keyless

  key <- Sys.getenv(key_var)
  if (!nzchar(key)) {
    stop(sprintf(
      "call_api: no API key found for provider '%s'.\nSet %s in ~/.Renviron and restart R.",
      provider, key_var
    ), call. = FALSE)
  }
  key
}


#' Build the chat endpoint URL for a provider + model combination.
#'
#' Resolution order:
#'   1. base_url override (openai_compat family only): caller supplies base host.
#'      -- Azure-style (template with {model} in path): replaces host in template.
#'      -- Standard OpenAI-style: appends /v1/chat/completions.
#'   2. chat_endpoint_template from registry: substitutes {model} and {base_url}.
#'   3. chat_endpoint (fixed URL) from registry.
#'
#' @noRd
.build_endpoint_url <- function(provider, model, base_url, prov_reg) {
  family <- prov_reg$handler_family %||% "openai_compat"

  # ------------------------------------------------------------------
  # base_url override (openai_compat family only)
  # ------------------------------------------------------------------
  if (!is.null(base_url) && identical(family, "openai_compat")) {
    base_clean <- gsub("/$", "", base_url)

    # Azure-style: template encodes the full path with {model}.
    # Swap just the host so the deployment path and api-version survive.
    tpl <- prov_reg$chat_endpoint_template %||% prov_reg$endpoint_template
    if (!is.null(tpl) && grepl("{model}", tpl, fixed = TRUE)) {
      old_host <- sub("^(https?://[^/]+).*", "\\1", tpl)
      url      <- sub(old_host, base_clean, tpl, fixed = TRUE)
      return(gsub("{model}", model, url, fixed = TRUE))
    }

    # Standard OpenAI-compat: base_url + /v1/chat/completions
    return(paste0(base_clean, "/v1/chat/completions"))
  }

  # ------------------------------------------------------------------
  # Template from registry (Gemini, Azure default, Ollama)
  # ------------------------------------------------------------------
  tpl <- prov_reg$chat_endpoint_template %||% prov_reg$endpoint_template
  if (!is.null(tpl)) {
    url <- gsub("{model}",    model %||% "",          tpl, fixed = TRUE)
    url <- gsub("{base_url}", "http://localhost:11434", url, fixed = TRUE)
    return(url)
  }

  # ------------------------------------------------------------------
  # Fixed endpoint (Anthropic, OpenAI)
  # ------------------------------------------------------------------
  ep <- prov_reg$chat_endpoint
  if (!is.null(ep)) return(ep)

  stop(sprintf(
    "call_api: no chat endpoint configured for provider '%s'. Check inst/model_tiers.json.",
    provider
  ), call. = FALSE)
}


# ==============================================================================
# Request builders  (one per handler family)
# Each returns an httr2_request object ready for req_perform().
# ==============================================================================

#' @noRd
.build_anthropic_request <- function(endpoint, model, prompt_str,
                                     max_tokens, api_key, prov_reg,
                                     images = NULL) {
  # Multi-modal: text block + one image block per base64 PNG string.
  # Text-only: content is just the prompt string (saves a JSON nesting level).
  if (!is.null(images) && length(images) > 0L) {
    content <- c(
      list(list(type = "text", text = prompt_str)),
      lapply(unname(images), function(b64) list(
        type   = "image",
        source = list(type = "base64", media_type = "image/png", data = b64)
      ))
    )
  } else {
    content <- prompt_str
  }

  httr2::request(endpoint) |>
    httr2::req_headers(
      "x-api-key"         = api_key,
      # API version header read from registry; update JSON when Anthropic changes it
      "anthropic-version" = prov_reg$api_version_header %||% "2023-06-01",
      "content-type"      = "application/json"
    ) |>
    httr2::req_body_json(list(
      model      = model,
      max_tokens = as.integer(max_tokens),
      messages   = list(list(role = "user", content = content))
    )) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(resp) FALSE)
}


#' @noRd
.build_gemini_request <- function(endpoint, model, prompt_str,
                                  max_tokens, api_key, prov_reg,
                                  images = NULL) {
  # Multi-modal: text part + one inlineData part per base64 PNG string.
  if (!is.null(images) && length(images) > 0L) {
    parts <- c(
      list(list(text = prompt_str)),
      lapply(unname(images), function(b64) list(
        inlineData = list(mimeType = "image/png", data = b64)
      ))
    )
  } else {
    parts <- list(list(text = prompt_str))
  }

  # Gemini auth: API key as query param (auth_type = "query")
  httr2::request(endpoint) |>
    httr2::req_url_query(key = api_key) |>
    httr2::req_headers("Content-Type" = "application/json") |>
    httr2::req_body_json(list(
      contents         = list(list(parts = parts)),
      generationConfig = list(maxOutputTokens = as.integer(max_tokens))
    )) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(resp) FALSE)
}


#' @noRd
.build_openai_compat_request <- function(endpoint, model, prompt_str,
                                         max_tokens, api_key, prov_reg,
                                         images = NULL) {
  # Body max_tokens field name varies by provider:
  #   - Most providers:  "max_tokens"
  #   - Azure o-series:  "max_completion_tokens" (set in registry)
  # The correct key is stored in prov_reg$body_max_tokens_key.
  max_tokens_key <- prov_reg$body_max_tokens_key %||% "max_tokens"

  # Multi-modal: text block + one image_url block per base64 PNG string.
  if (!is.null(images) && length(images) > 0L) {
    content <- c(
      list(list(type = "text", text = prompt_str)),
      lapply(unname(images), function(b64) list(
        type      = "image_url",
        image_url = list(url = paste0("data:image/png;base64,", b64))
      ))
    )
  } else {
    content <- prompt_str
  }

  body <- list(
    model    = model,
    messages = list(list(role = "user", content = content))
  )
  body[[max_tokens_key]] <- as.integer(max_tokens)

  auth_type <- prov_reg$auth_type %||% "bearer"

  req <- httr2::request(endpoint) |>
    httr2::req_body_json(body) |>
    httr2::req_timeout(120) |>
    httr2::req_error(is_error = function(resp) FALSE)

  # Apply auth header based on provider's auth_type
  if (identical(auth_type, "bearer")) {
    req <- req |> httr2::req_headers(
      "Authorization" = paste("Bearer", api_key),
      "Content-Type"  = "application/json"
    )
  } else if (identical(auth_type, "x-api-key")) {
    req <- req |> httr2::req_headers(
      `api-key`      = api_key,
      `Content-Type` = "application/json"
    )
  } else if (identical(auth_type, "none")) {
    req <- req |> httr2::req_headers("Content-Type" = "application/json")
  } else {
    stop(sprintf(
      "call_api: unsupported auth_type '%s' for provider. Check inst/model_tiers.json.",
      auth_type
    ), call. = FALSE)
  }

  req
}


# ==============================================================================
# Response parsers  (one per handler family)
# Each takes the raw httr2 response and provider name; returns a list:
#   list(text = "<response string>", tokens = list(input = N, output = N))
# Token counts are NA_integer_ when the provider does not report them.
# ==============================================================================

#' @noRd
.parse_anthropic_response <- function(resp, provider) {
  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf("call_api (%s): HTTP %d: %s",
                 provider, status, body$error$message %||% "(no message)"),
         call. = FALSE)
  }
  body        <- httr2::resp_body_json(resp)
  text_blocks <- Filter(function(b) identical(b$type, "text"), body$content)
  if (length(text_blocks) == 0L) {
    stop(sprintf("call_api (%s): response contained no text blocks.", provider),
         call. = FALSE)
  }
  list(
    text   = text_blocks[[1L]]$text,
    tokens = list(
      input  = body$usage$input_tokens  %||% NA_integer_,
      output = body$usage$output_tokens %||% NA_integer_
    )
  )
}


#' @noRd
.parse_gemini_response <- function(resp, provider) {
  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body_err <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf("call_api (%s): HTTP %d: %s",
                 provider, status, body_err$error$message %||% "(no message)"),
         call. = FALSE)
  }
  parsed     <- httr2::resp_body_json(resp)
  candidates <- parsed$candidates
  if (is.null(candidates) || length(candidates) == 0L) {
    feedback <- parsed$promptFeedback$blockReason
    if (!is.null(feedback)) {
      stop(sprintf("call_api (%s): prompt blocked by safety filter: %s",
                   provider, feedback), call. = FALSE)
    }
    stop(sprintf("call_api (%s): response contained no candidates.", provider),
         call. = FALSE)
  }
  parts <- candidates[[1L]]$content$parts
  if (is.null(parts) || length(parts) == 0L) {
    stop(sprintf("call_api (%s): candidate contained no content parts.", provider),
         call. = FALSE)
  }
  # Concatenate all text parts (Gemini can split a long response)
  text <- paste(vapply(parts, function(p) p$text %||% "", character(1)), collapse = "")
  list(
    text   = text,
    tokens = list(
      input  = parsed$usageMetadata$promptTokenCount     %||% NA_integer_,
      output = parsed$usageMetadata$candidatesTokenCount %||% NA_integer_
    )
  )
}


#' @noRd
.parse_openai_compat_response <- function(resp, provider) {
  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body_err <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf("call_api (%s): HTTP %d: %s",
                 provider, status, body_err$error$message %||% "(no message)"),
         call. = FALSE)
  }
  parsed  <- httr2::resp_body_json(resp)
  choices <- parsed$choices
  if (is.null(choices) || length(choices) == 0L) {
    stop(sprintf("call_api (%s): response contained no choices.", provider),
         call. = FALSE)
  }
  content <- choices[[1L]]$message$content
  if (is.null(content) || !nzchar(trimws(content))) {
    finish_reason <- choices[[1L]]$finish_reason %||% "unknown"
    stop(sprintf("call_api (%s): empty response (finish_reason: %s).",
                 provider, finish_reason), call. = FALSE)
  }
  list(
    text   = content,
    tokens = list(
      input  = parsed$usage$prompt_tokens     %||% NA_integer_,
      output = parsed$usage$completion_tokens %||% NA_integer_
    )
  )
}


# ==============================================================================
# Main exported function
# ==============================================================================

#' Call Any Configured LLM with a Single Prompt String
#'
#' Generic provider-neutral function. Resolves the provider, model, API key,
#' and endpoint from the registry (\code{inst/model_tiers.json} plus any
#' session entries added via \code{\link{register_provider}}), builds the
#' provider-appropriate HTTP request, and returns the model's response as a
#' plain character string.
#'
#' Individual provider functions (\code{\link{call_anthropic_api}},
#' \code{\link{call_gemini_api}}, etc.) are thin wrappers around this
#' function and remain available for backward compatibility and for use as
#' \code{llm_fn} arguments.
#'
#' @param prompt_str Character. A length-1 string containing the complete
#'   prompt to submit.
#' @param provider Character. Provider name: \code{"anthropic"},
#'   \code{"gemini"}, \code{"openai"}, \code{"azure"}, \code{"ollama"}, or
#'   any name registered with \code{\link{register_provider}}.
#'   Default \code{NULL} uses \code{options("TaxaID.provider")}, which is set
#'   automatically by \code{library(TaxaTools)} based on detected API keys.
#' @param tier Character. Capability tier when \code{model = NULL}:
#'   \code{"fast"} (cheapest/smallest), \code{"mid"} (balanced, default), or
#'   \code{"top"} (most capable). Ignored when \code{model} is specified.
#'   Tier-to-model mapping is discovered live from the provider's
#'   \code{/models} endpoint (see \code{\link{list_models}}).
#' @param model Character. Exact model identifier. Overrides \code{tier}
#'   resolution. Use to pin a specific version for reproducibility.
#' @param max_tokens Integer. Maximum tokens in the response (default 3000).
#'   The correct request body field for the provider
#'   (\code{max_tokens} vs \code{max_completion_tokens}) is read from the
#'   registry automatically.
#' @param api_key Character. API key override. Default \code{NULL} reads the
#'   key from the environment variable named in the provider's registry entry
#'   (e.g. \code{ANTHROPIC_API_KEY}). Keyless providers (Ollama) ignore this.
#' @param base_url Character. Base URL override for OpenAI-compatible providers
#'   (OpenAI, Azure, Ollama, custom registered providers). Default \code{NULL}
#'   uses the provider's registered endpoint.
#'   \itemize{
#'     \item For Ollama: change the host/port, e.g.
#'       \code{base_url = "http://remote-server:11434"}.
#'     \item For OpenAI-compatible proxies: supply the proxy base URL.
#'     \item For Azure: replaces the host in the endpoint template while
#'       preserving the deployment path and API version.
#'   }
#' @param images Named list of base64-encoded PNG strings, as returned by
#'   \code{.render_pdf_pages()} in the TaxaFetch PDF pipeline. Default
#'   \code{NULL} (text-only call). When supplied, the prompt and images are
#'   sent as a multi-modal message using the provider's vision format:
#'   Anthropic image content blocks, Gemini \code{inlineData} parts, or
#'   OpenAI \code{image_url} blocks. Requires a vision-capable model
#'   (e.g. Claude Sonnet, Gemini 2.5 Flash, GPT-4o).
#' @param show_tokens Logical. When \code{TRUE}, prints a message after each
#'   call reporting input and output token counts (e.g.
#'   \code{"Tokens used — input: 312, output: 87"}). Default \code{FALSE} to
#'   avoid output in non-interactive workflows. Token counts are retrieved from
#'   the provider's response body; \code{NA} is reported when a provider does
#'   not return usage information.
#' @param max_input_tokens Integer or \code{NULL}. When non-\code{NULL},
#'   estimates the prompt length as \code{ceiling(nchar(prompt_str) / 3.5)}
#'   (a conservative characters-per-token heuristic) and stops with an
#'   informative error before making the HTTP request if the estimate exceeds
#'   the limit. Use this as a pre-flight guard against accidentally sending very
#'   large prompts. Default \code{NULL} (no check performed).
#'
#' @return A length-1 character string containing the model's response text.
#'   The following attributes are attached:
#'   \describe{
#'     \item{\code{"model"}}{The resolved model identifier.}
#'     \item{\code{"provider"}}{The provider name used.}
#'     \item{\code{"tokens"}}{A named list with elements \code{input} and
#'       \code{output} (integers) giving the token counts reported by the
#'       provider. Both are \code{NA_integer_} when the provider does not
#'       return usage information.}
#'   }
#'   Stops on any non-200 HTTP status with a provider-specific error message.
#'
#' @details
#' \strong{Adding a new provider:}
#' Any provider that implements the OpenAI Chat Completions API can be added
#' for the current session with \code{\link{register_provider}}. The function
#' then dispatches via the \code{openai_compat} handler automatically.
#'
#' \strong{Ollama quality note:}
#' Local Ollama models vary substantially in their ability to produce the
#' structured JSON and CSV output that TaxaID functions expect. Results are
#' less reliable than cloud providers, especially for obscure taxa. A warning
#' is emitted when Ollama is selected.
#'
#' \strong{Using as llm_fn:}
#' \code{call_api} is the default \code{llm_fn} throughout the TaxaID
#' ecosystem. Individual provider functions can still be passed as
#' \code{llm_fn} for explicit provider control:
#' \preformatted{
#' # Use Gemini for a specific call
#' prompt_api(prompt, llm_fn = call_gemini_api)
#'
#' # Use a fast model for a batch task
#' prompt_api(prompt, llm_fn = function(p, ...) call_api(p, tier = "fast"))
#'
#' # Set session default to OpenAI
#' options(TaxaID.provider = "openai")
#' }
#'
#' @seealso \code{\link{register_provider}}, \code{\link{list_models}},
#'   \code{\link{set_model}}, \code{\link{refresh_models}},
#'   \code{\link{call_anthropic_api}}, \code{\link{call_gemini_api}},
#'   \code{\link{call_openai_api}}, \code{\link{call_azure_api}},
#'   \code{\link{call_ollama_api}}
#'
#' @importFrom httr2 request req_headers req_body_json req_url_query req_error
#'   req_perform req_timeout resp_status resp_body_json
#' @export
#'
#' @examples
#' \dontrun{
#' # Auto-detected provider (set by library(TaxaTools))
#' answer <- call_api("What phylum do sea urchins belong to?")
#'
#' # Explicit provider and tier
#' answer <- call_api("What phylum do sea urchins belong to?",
#'                    provider = "gemini", tier = "fast")
#'
#' # Pinned model for reproducibility
#' answer <- call_api("What phylum do sea urchins belong to?",
#'                    provider = "anthropic", model = "claude-sonnet-4-5")
#'
#' # Registered custom provider (see register_provider())
#' register_provider("xai", "XAI_API_KEY", "https://api.x.ai",
#'   fallback_models = list(mid = "grok-3"))
#' answer <- call_api("What phylum do sea urchins belong to?",
#'                    provider = "xai")
#' }
call_api <- function(prompt_str,
                     provider         = NULL,
                     tier             = c("mid", "fast", "top"),
                     model            = NULL,
                     max_tokens       = 3000L,
                     api_key          = NULL,
                     base_url         = NULL,
                     images           = NULL,
                     show_tokens      = FALSE,
                     max_input_tokens = NULL) {

  tier <- match.arg(tier)

  if (!is.character(prompt_str) || length(prompt_str) != 1L) {
    stop("call_api: 'prompt_str' must be a length-1 character string.", call. = FALSE)
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("call_api: package 'httr2' is required. ",
         "Install with: install.packages('httr2')", call. = FALSE)
  }

  # Pre-flight token size guard (before any HTTP call)
  if (!is.null(max_input_tokens)) {
    estimated_tokens <- ceiling(nchar(prompt_str) / 3.5)
    if (estimated_tokens > max_input_tokens) {
      stop(sprintf(
        "call_api: estimated prompt size (%d tokens) exceeds max_input_tokens (%d).\n%s",
        estimated_tokens, max_input_tokens,
        "Shorten the prompt or increase max_input_tokens to proceed."
      ), call. = FALSE)
    }
  }

  provider <- .resolve_provider(provider)
  registry <- .get_registry()
  prov_reg <- registry$providers[[provider]]

  if (is.null(prov_reg)) {
    stop(sprintf(
      "call_api: unknown provider '%s'. Use register_provider() to add it.",
      provider
    ), call. = FALSE)
  }

  # Ollama: warn that local model quality varies
  if (identical(provider, "ollama")) {
    warning(
      "call_api: Ollama uses local open-weight models. ",
      "Structured output quality for taxonomic tasks varies by model. ",
      "Recommended minimum: qwen2.5:14b. Verify results carefully.",
      call. = FALSE
    )
  }

  model    <- model %||% .resolve_model(provider, tier)
  api_key  <- .resolve_api_key(provider, api_key, registry)
  endpoint <- .build_endpoint_url(provider, model, base_url, prov_reg)
  family   <- prov_reg$handler_family %||% "openai_compat"

  # Build the provider-appropriate HTTP request
  req <- switch(family,
    anthropic     = .build_anthropic_request(endpoint, model, prompt_str, max_tokens, api_key, prov_reg, images),
    gemini        = .build_gemini_request(endpoint, model, prompt_str, max_tokens, api_key, prov_reg, images),
    openai_compat = .build_openai_compat_request(endpoint, model, prompt_str, max_tokens, api_key, prov_reg, images),
    stop(sprintf(
      "call_api: unknown handler_family '%s' for provider '%s'. Check inst/model_tiers.json.",
      family, provider
    ), call. = FALSE)
  )

  # Perform the HTTP call; translate connection errors into clear messages
  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("Could not connect|Connection refused|Could not resolve",
                msg, ignore.case = TRUE)) {
        if (identical(provider, "ollama")) {
          stop(paste0(
            "call_api (ollama): cannot connect to Ollama at ",
            base_url %||% "http://localhost:11434", ".\n",
            "Make sure Ollama is installed and running: https://ollama.com"
          ), call. = FALSE)
        }
        if (identical(provider, "azure")) {
          stop(paste0(
            "call_api (azure): cannot connect to the DOI Azure endpoint.\n",
            "This API requires connection to a DOI computer system or DOI VPN."
          ), call. = FALSE)
        }
      }
      stop(sprintf("call_api (%s): HTTP request failed: %s", provider, msg),
           call. = FALSE)
    }
  )

  # Parse the provider-appropriate response (returns list(text, tokens))
  parsed <- switch(family,
    anthropic     = .parse_anthropic_response(resp, provider),
    gemini        = .parse_gemini_response(resp, provider),
    openai_compat = .parse_openai_compat_response(resp, provider),
    stop(sprintf("call_api: unknown handler_family '%s'.", family), call. = FALSE)
  )

  text   <- parsed$text
  tokens <- parsed$tokens

  if (isTRUE(show_tokens)) {
    message(sprintf("Tokens used \u2014 input: %s, output: %s",
                    if (is.na(tokens$input))  "NA" else as.character(tokens$input),
                    if (is.na(tokens$output)) "NA" else as.character(tokens$output)))
  }

  attr(text, "model")    <- model
  attr(text, "provider") <- provider
  attr(text, "tokens")   <- tokens
  text
}
