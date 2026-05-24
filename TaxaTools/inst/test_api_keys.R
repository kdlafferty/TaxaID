# test_api_keys.R
# Test that configured LLM API keys are valid and reachable.
#
# Usage:
#   source(system.file("test_api_keys.R", package = "TaxaTools"))
#   # or run directly from the TaxaTools inst/ directory
#
# Tests each provider whose key is set in the environment.
# Azure OpenAI requires a DOI computer system or DOI VPN connection.
# ==============================================================================

library(TaxaTools)


# Should see: "TaxaID: Using Anthropic as LLM provider."
# And both options will be set:
getOption("TaxaID.provider")   # "anthropic"
identical(getOption("TaxaID.llm_fn"), call_api)  # TRUE

# 1. Generic call — uses auto-detected provider
answer <- call_api("What phylum do sea urchins belong to?")
attr(answer, "provider")   # "anthropic"
attr(answer, "model")      # "claude-sonnet-4-6"

# 2. Explicit provider
call_api("What phylum?", provider = "gemini", tier = "fast")

# 3. Tier
call_api("What phylum?", tier = "top")

# 4. Thin wrappers still work (backward compat)
call_anthropic_api("What phylum?", tier = "fast")
call_gemini_api("What phylum?")

# 5. Switch provider for the session
options(TaxaID.provider = "gemini")
call_api("What phylum?")   # now hits Gemini

# 6. Register a custom provider (e.g. xAI Grok if you get a key)
register_provider("xai", "XAI_API_KEY", "https://api.x.ai",
                  fallback_models = list(fast = "grok-3-mini", mid = "grok-3", top = "grok-3"))
list_models("xai")

##OLD BELOW

TEST_PROMPT <- "Reply with exactly one word: hello"

providers <- list(
  list(
    name   = "Anthropic",
    key    = "ANTHROPIC_API_KEY",
    fn     = TaxaTools::call_anthropic_api,
    note   = NULL
  ),
  list(
    name   = "Google Gemini",
    key    = "GEMINI_API_KEY",
    fn     = TaxaTools::call_gemini_api,
    note   = NULL
  ),
  list(
    name   = "OpenAI",
    key    = "OPENAI_API_KEY",
    fn     = TaxaTools::call_openai_api,
    note   = NULL
  ),
  list(
    name   = "Azure OpenAI (DOI)",
    key    = "AZURE_OPENAI_API_KEY",
    fn     = TaxaTools::call_azure_api,
    note   = "Requires DOI network or DOI VPN connection"
  ),
  list(
    name   = "Ollama (local)",
    key    = NULL,   # no key needed
    fn     = TaxaTools::call_ollama_api,
    note   = "Requires Ollama running locally (https://ollama.com)"
  )
)

cat("\n")
cat(strrep("=", 60), "\n")
cat("  TaxaTools API key test\n")
cat(strrep("=", 60), "\n\n")

results <- list()

for (p in providers) {

  # Skip keyed providers if key is not set
  if (!is.null(p$key) && !nzchar(Sys.getenv(p$key))) {
    cat(sprintf("  [ SKIP ] %s — %s not set in environment\n",
                p$name, p$key))
    results[[p$name]] <- "skipped"
    next
  }

  if (!is.null(p$note)) {
    cat(sprintf("  [ .... ] %s  (%s)\n", p$name, p$note))
  } else {
    cat(sprintf("  [ .... ] %s\n", p$name))
  }

  result <- tryCatch({
    response <- p$fn(TEST_PROMPT)
    if (!is.character(response) || !nzchar(trimws(response))) {
      stop("empty response")
    }
    list(ok = TRUE, text = trimws(response))
  }, error = function(e) {
    list(ok = FALSE, msg = conditionMessage(e))
  })

  # Overwrite the [ .... ] line with result
  if (result$ok) {
    cat(sprintf("\r  [  OK  ] %s — response: \"%s\"\n",
                p$name, result$text))
    results[[p$name]] <- "ok"
  } else {
    cat(sprintf("\r  [ FAIL ] %s\n", p$name))
    cat(sprintf("           %s\n", result$msg))
    results[[p$name]] <- "fail"
  }
}

# Summary
n_ok      <- sum(vapply(results, identical, logical(1), "ok"))
n_fail    <- sum(vapply(results, identical, logical(1), "fail"))
n_skipped <- sum(vapply(results, identical, logical(1), "skipped"))

cat("\n")
cat(strrep("-", 60), "\n")
cat(sprintf("  Results: %d passed, %d failed, %d skipped\n",
            n_ok, n_fail, n_skipped))
cat(strrep("-", 60), "\n\n")

if (n_fail > 0L) {
  message("One or more API keys failed. Check the error messages above.")
} else if (n_ok == 0L) {
  message("No keys were tested. Set at least one API key in ~/.Renviron and restart R.")
} else {
  message("All tested providers responded successfully.")
}
