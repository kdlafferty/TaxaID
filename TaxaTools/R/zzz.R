# ==============================================================================
# zzz.R
# TaxaTools — package load hooks
#
# .onAttach():  Detect available LLM API keys and set options(TaxaID.llm_fn)
# ==============================================================================


#' Detect available LLM providers and set the default
#' @noRd
.detect_llm_provider <- function() {

  # Provider registry: env var → provider label → call function name
  providers <- list(
    list(key = "ANTHROPIC_API_KEY", label = "Anthropic", fn = "call_anthropic_api"),
    list(key = "GEMINI_API_KEY",    label = "Gemini",    fn = "call_gemini_api"),
    list(key = "OPENAI_API_KEY",    label = "OpenAI",    fn = "call_openai_api")
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
  if (!is.null(getOption("TaxaID.llm_fn"))) return(invisible())

  available <- .detect_llm_provider()
  n <- length(available)

  if (n == 0L) {
    packageStartupMessage(
      "TaxaID: No LLM API keys detected in environment variables.\n",
      "  LLM-dependent functions (habitat assignment, text generation, etc.) ",
      "will not work until a key is set.\n",
      "  Add one of the following to ~/.Renviron and restart R:\n",
      "    ANTHROPIC_API_KEY=your_key   (Anthropic Claude)\n",
      "    GEMINI_API_KEY=your_key      (Google Gemini - free tier available)\n",
      "    OPENAI_API_KEY=your_key      (OpenAI)\n",
      "  Or use a local model: llm_fn = TaxaTools::call_ollama_api"
    )
    return(invisible())
  }

  # Use first available (priority: Anthropic > Gemini > OpenAI)
  chosen <- available[[1L]]
  fn <- get(chosen$fn, envir = asNamespace("TaxaTools"))
  options(TaxaID.llm_fn = fn)

  if (n == 1L) {
    packageStartupMessage(
      sprintf("TaxaID: Using %s as LLM provider.", chosen$label)
    )
  } else {
    other_labels <- vapply(available[-1L], `[[`, character(1L), "label")
    packageStartupMessage(
      sprintf("TaxaID: Multiple LLM providers available (%s).",
              paste(vapply(available, `[[`, character(1L), "label"),
                    collapse = ", ")),
      sprintf("\n  Using %s (first available). Change with:", chosen$label),
      sprintf("\n    options(TaxaID.llm_fn = TaxaTools::%s)",
              available[[2L]]$fn)
    )
  }
}
