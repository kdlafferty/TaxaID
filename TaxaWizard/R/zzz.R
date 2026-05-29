# ==============================================================================
# zzz.R
# TaxaWizard — package load hook
#
# .onAttach(): Detect available LLM API keys and set TaxaID.provider /
#   TaxaID.llm_fn options if TaxaTools has not already done so.
#   Mirrors TaxaTools' detection priority so that loading TaxaWizard
#   alone is sufficient — users do not need library(TaxaTools) separately.
# ==============================================================================


#' @noRd
.onAttach <- function(libname, pkgname) {

  # TaxaTools already configured — nothing to do
  if (!is.null(getOption("TaxaID.provider"))) return(invisible())

  # Detect available providers (same priority as TaxaTools)
  key_map <- list(
    list(key = "ANTHROPIC_API_KEY",    name = "anthropic"),
    list(key = "GEMINI_API_KEY",       name = "gemini"),
    list(key = "OPENAI_API_KEY",       name = "openai"),
    list(key = "AZURE_OPENAI_API_KEY", name = "azure")
  )

  for (p in key_map) {
    if (nzchar(Sys.getenv(p$key, unset = ""))) {
      options(TaxaID.provider = p$name)

      # Set llm_fn if TaxaTools is installed (enables the non-Anthropic bridge
      # in .call_llm without requiring the user to call library(TaxaTools))
      if (is.null(getOption("TaxaID.llm_fn")) &&
          requireNamespace("TaxaTools", quietly = TRUE)) {
        options(TaxaID.llm_fn = TaxaTools::call_api)
      }
      break
    }
  }
}
