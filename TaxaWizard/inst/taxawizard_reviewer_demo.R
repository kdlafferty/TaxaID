# =============================================================================
# TaxaWizard -- Reviewer Demo Script
# =============================================================================
# Runs the exported TaxaWizard functions end to end for a code + domain
# review, using Azure OpenAI (DOI) as the LLM backend. Companion to
# inst/taxawizard_review.Rmd (this package's review write-up).
#
# WHAT THIS ASSUMES
#   - TaxaWizard is installed (devtools::install() from the package root, or
#     library(TaxaWizard) if already on your library path).
#   - TaxaTools is installed and AZURE_OPENAI_API_KEY is set in ~/.Renviron
#     (DOI employees only; requires DOI network or DOI VPN -- see
#     TaxaTools::call_azure_openai_api()'s own documentation).
#   - You are running this in an interactive R session (RStudio console or
#     `R` at the terminal). workflow_create()/workflow_fix() both require
#     interactive() and will error in a plain `Rscript` batch run -- source
#     this file line by line, or run each section's chunk directly, rather
#     than `Rscript this_file.R`.
#
# HOW TAXAWIZARD TALKS TO AN LLM
#   TaxaWizard has no hard dependency on TaxaTools (Suggests only -- see its
#   CLAUDE.md: "no TaxaID package depends on it"). Every entry point that
#   calls an LLM (workflow_create(), workflow_engine(), workflow_fix(),
#   workflow_app(annotate = "llm"), annotate_script(mode = "llm")) accepts an
#   llm_fn argument for exactly this reason. Section 0 below builds one
#   explicit Azure-backed llm_fn and reuses it everywhere in this script,
#   rather than relying on TaxaWizard's own automatic non-Anthropic bridge
#   (R/zzz.R's .onAttach() + R/api.R's .call_llm(), which auto-detects
#   AZURE_OPENAI_API_KEY and would also work) -- passing llm_fn explicitly
#   is more robust when more than one provider key is set in the same
#   environment, since it removes any ambiguity about which one gets used.
# =============================================================================

library(TaxaWizard)

# --- 0. Build an Azure-backed llm_fn -----------------------------------------
# TaxaWizard's llm_fn contract (see ?workflow_create): a function accepting
# messages/system_prompt/model/max_tokens and returning ONE character string
# (plain text or JSON) -- never a parsed list. TaxaTools::call_api() takes a
# single flattened prompt string, so the conversation history + system
# prompt are joined into one string before the call, exactly as TaxaWizard's
# own internal Anthropic-alternative bridge does (R/api.R's .call_llm()).

stopifnot(requireNamespace("TaxaTools", quietly = TRUE))
stopifnot(nzchar(Sys.getenv("AZURE_OPENAI_API_KEY", unset = "")))

azure_llm_fn <- function(messages, system_prompt, model, max_tokens) {
  history_text <- paste(
    vapply(messages, function(m) {
      role <- if (identical(m$role, "user")) "User" else "Assistant"
      paste0(role, ": ", m$content)
    }, character(1L)),
    collapse = "\n\n"
  )
  combined <- paste0(system_prompt, "\n\n---\n\n", history_text)
  TaxaTools::call_api(combined, provider = "azure_openai", max_tokens = max_tokens)
}

# Quick sanity check: a bare (non-TaxaWizard) call to confirm the Azure
# connection itself works before spending calls on the engine below.
cat(TaxaTools::call_api("Reply with exactly one word: pong",
                        provider = "azure_openai"), "\n")


# --- 1. Offline checks (no API calls, no cost) -------------------------------
# Exercises the graph engine and response parser directly -- useful for
# confirming the package installed correctly and the workflow graph loads,
# without spending any LLM calls.

# All valid pipeline paths from raw sequence data to a consensus call.
paths <- TaxaWizard:::.compute_paths("sequences", "consensus")
cat(sprintf("Found %d path(s) from sequences -> consensus.\n", length(paths)))
cat(TaxaWizard:::.describe_paths(paths), "\n")

# The three-tier JSON-recovery parser that protects the conversation from a
# malformed/chatty LLM response (see inst/taxawizard_review.Rmd's Automated
# Tests section for what each tier covers).
TaxaWizard:::.parse_engine_response(
  '{"status": "incomplete", "message": "What marker did you sequence?"}'
)


# --- 2. Single live engine call ----------------------------------------------
# workflow_engine() is the stateless core workflow_create() is built on --
# useful for a reviewer who wants to see one classify-phase response without
# driving the full interactive chat loop. This makes exactly one real Azure
# call.

history <- list(list(
  role    = "user",
  content = paste(
    "I have 12S eDNA amplicon sequences from a coral reef survey in",
    "Hawaii and want to identify the fish species present, with a",
    "full Bayesian posterior (likelihood x occurrence prior)."
  )
))

result <- workflow_engine(history = history, llm_fn = azure_llm_fn)
str(result[c("status", "phase", "message", "input_type", "output_type")])


# --- 3. Full interactive interview -------------------------------------------
# The main user-facing entry point. Runs a real multi-turn conversation in
# the R console: classify -> path_select -> parameterize -> script
# generation. Type 'quit' at any prompt to exit early.
#
#   workflow_create(mode = "console", llm_fn = azure_llm_fn,
#                   output_dir = tempdir())
#
# `mode = "viewer"`/`"browser"` open the same interview in a Shiny gadget
# (RStudio Viewer pane / a browser tab) instead of the plain console loop --
# requires the `shiny` package. Try:
#
#   workflow_create(mode = "browser", llm_fn = azure_llm_fn,
#                   output_dir = tempdir())
#
# Not run automatically by this script (interactive() input required) --
# uncomment and run directly in your console.


# --- 4. Resuming after a script error: workflow_fix() ------------------------
# After running a script generated in Section 3 and hitting a real error,
# call (with no arguments) to paste the error interactively:
#
#   workflow_fix()
#
# workflow_fix() reuses the llm_fn saved with the session in Section 3 --
# it does not need azure_llm_fn passed again. Requires a saved session (i.e.
# Section 3 must have run and generated a workflow first); otherwise it
# errors with "No saved workflow session found."


# --- 5. Script-to-Shiny-app conversion: workflow_app() -----------------------
# Builds a tiny TaxaWizard-style script by hand (so this section runs with
# no LLM call and no dependency on Section 3 having completed) and converts
# it into a standalone Shiny app.

demo_dir <- file.path(tempdir(), "taxawizard_demo")
dir.create(demo_dir, showWarnings = FALSE)

demo_script <- c(
  "library(TaxaWizard)",
  "library(TaxaTools)",
  "",
  "debug_mode <- TRUE",
  "debug_n    <- 20L",
  "",
  "checkpoint_dir <- file.path(tempdir(), \".workflow_checkpoints\")",
  "if (!dir.exists(checkpoint_dir)) dir.create(checkpoint_dir, recursive = TRUE)",
  "total_steps <- 1L",
  "",
  ".run_step <- function(step_id, description, code_expr, env = parent.frame()) {",
  "  cache_file <- file.path(checkpoint_dir, sprintf(\"step_%02d.rds\", step_id))",
  "  if (file.exists(cache_file)) return(readRDS(cache_file))",
  "  message(sprintf(\"Step %d/%d: %s\", step_id, total_steps, description))",
  "  result <- eval(code_expr, envir = env)",
  "  saveRDS(result, cache_file)",
  "  result",
  "}",
  "",
  "# --- User Parameters ---",
  "input_file <- \"match_data.csv\"",
  "min_score <- 97",
  "",
  "# --- Step 1: Load and filter match data ---",
  "step_1_result <- .run_step(1, \"Load and filter match data\", quote({",
  "  read.csv(input_file)",
  "}))",
  "",
  "# --- Workflow complete ---",
  "message(\"Workflow complete.\")"
)
writeLines(demo_script, file.path(demo_dir, "demo_workflow.R"))

app_path <- workflow_app(
  script_path = file.path(demo_dir, "demo_workflow.R"),
  output_dir  = demo_dir,
  launch      = FALSE   # set TRUE (or omit) to actually launch the app
)
cat("Generated app:", app_path, "\n")
# Inspect the generated app, or launch it yourself:
#   shiny::runApp(demo_dir)


# --- 6. Guided annotation of a generic (non-TaxaWizard) script --------------
# annotate_script() is what workflow_app() falls back to for a script with
# no "# --- Step N ---" markers. Two modes: "self" (console Q&A, no LLM) and
# "llm" (one LLM call proposes parameters/steps, then you confirm). This
# demonstrates the LLM-guided path with azure_llm_fn.

generic_script <- c(
  "library(TaxaFetch)",
  "",
  "search_lat <- 34.45",
  "search_lon <- -119.85",
  "search_radius_deg <- 2",
  "",
  "occ <- TaxaFetch::fetch_gbif_occurrences(",
  "  lat = search_lat, lon = search_lon, radius_deg = search_radius_deg",
  ")",
  "occ_clean <- TaxaFetch::filter_gbif_quality(occ)"
)
writeLines(generic_script, file.path(demo_dir, "generic_script.R"))

# Uncomment to run (makes one Azure call, then asks for a y/n/edit
# confirmation at the console -- see ?annotate_script):
#
#   parsed <- annotate_script(file.path(demo_dir, "generic_script.R"),
#                             mode = "llm", llm_fn = azure_llm_fn)
#   str(parsed, max.level = 1)


# --- 7. Deprecated wrappers ---------------------------------------------------
# workflow_chat()/workflow_gadget() are thin, still-exported wrappers around
# workflow_create(mode = "console"/"viewer") -- confirm they print a
# deprecation notice and forward correctly, without starting a second
# interactive session:
formals(workflow_chat)
formals(workflow_gadget)
