# ==============================================================================
# zzz.R
# TaxaTools — package load hooks
#
# .onAttach():  Detect available LLM API keys and set:
#   options(TaxaID.provider)  -- provider name string, read by call_api()
#   options(TaxaID.llm_fn)    -- set to call_api, for backward compat with
#                                ecosystem functions that use llm_fn defaults
# ==============================================================================


#' Detect available LLM providers and set the default
#' @noRd
.detect_llm_provider <- function() {

  # Priority: Anthropic > Gemini > OpenAI > Azure (DOI network/VPN required)
  providers <- list(
    list(key = "ANTHROPIC_API_KEY",    name = "anthropic",  label = "Anthropic"),
    list(key = "GEMINI_API_KEY",       name = "gemini",     label = "Gemini"),
    list(key = "OPENAI_API_KEY",       name = "openai",     label = "OpenAI"),
    list(key = "AZURE_OPENAI_API_KEY", name = "azure_openai", label = "Azure OpenAI (DOI)")
  )

  available <- list()
  for (p in providers) {
    val <- Sys.getenv(p$key, unset = "")
    if (nzchar(val)) {
      available <- c(available, list(p))
    }
  }

  available
}


.onAttach <- function(libname, pkgname) {

  # Skip in non-interactive sessions (CRAN checks, CI, scripts)
  if (!interactive()) return(invisible())

  # Respect any user-set option (e.g., from .Rprofile)
  if (!is.null(getOption("TaxaID.llm_fn")) ||
      !is.null(getOption("TaxaID.provider"))) return(invisible())

  available <- .detect_llm_provider()
  n <- length(available)

  if (n == 0L) {
    packageStartupMessage(
      "TaxaID: No LLM API keys detected in environment variables.\n",
      "  LLM-dependent functions (habitat assignment, text generation, etc.) ",
      "will not work until a key is set.\n",
      "  Add one of the following to ~/.Renviron and restart R:\n",
      "    ANTHROPIC_API_KEY=your_key       (Anthropic Claude)\n",
      "    GEMINI_API_KEY=your_key          (Google Gemini - free tier available)\n",
      "    OPENAI_API_KEY=your_key          (OpenAI)\n",
      "    AZURE_OPENAI_API_KEY=your_key    (Azure OpenAI - DOI employees only; requires DOI network or VPN)\n",
      "  Or use a local model: call_api(prompt, provider = 'ollama')"
    )
    return(invisible())
  }

  # Use first available (priority: Anthropic > Gemini > OpenAI > Azure)
  chosen <- available[[1L]]
  options(TaxaID.provider = chosen$name)
  options(TaxaID.llm_fn   = call_api)

  if (n == 1L) {
    msg <- sprintf("TaxaID: Using %s as LLM provider.", chosen$label)
    if (identical(chosen$name, "azure_openai")) {
      msg <- paste0(msg, "\n  NOTE: Azure OpenAI requires connection to a DOI computer system or DOI VPN.")
    }
    msg <- paste0(msg, "\n  NOTE: Cloud LLM providers transmit prompts to third-party servers.",
                  " Use provider = 'ollama' for local inference with sensitive data.")
    packageStartupMessage(msg)
  } else {
    if (identical(chosen$name, "azure_openai")) {
      doi_note <- "\n  NOTE: Azure OpenAI requires connection to a DOI computer system or DOI VPN."
    } else {
      doi_note <- ""
    }
    packageStartupMessage(
      sprintf("TaxaID: Multiple LLM providers available (%s).",
              paste(vapply(available, `[[`, character(1L), "label"),
                    collapse = ", ")),
      sprintf("\n  Using %s (first available). Change with:", chosen$label),
      sprintf('\n    options(TaxaID.provider = "%s")', available[[2L]]$name),
      doi_note,
      "\n  NOTE: Cloud LLM providers transmit prompts to third-party servers.",
      " Use provider = 'ollama' for local inference with sensitive data."
    )
  }
}
