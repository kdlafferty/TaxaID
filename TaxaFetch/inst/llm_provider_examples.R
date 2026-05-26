# =============================================================================
# LLM provider examples for TaxaFetch workflows
# =============================================================================
#
# These are drop-in replacements for the LLM submission block in any workflow.
# Everything before (build_habitat_prompt, build_scheme_prompt, etc.) and
# everything after (parse_hierarchical_habitat_response, assign_habitat_biological,
# etc.) is identical regardless of provider.
#
# Only the lines between #### PROVIDER BLOCK #### and #### END PROVIDER ####
# need to change when switching providers.
#
# SETUP — add keys to ~/.Renviron (one time only):
#   ANTHROPIC_API_KEY=sk-ant-...        # Anthropic (paid)
#   GEMINI_API_KEY=AIza...              # Gemini (free tier available)
#   OPENAI_API_KEY=sk-...              # OpenAI (paid)
#   # Ollama: no key needed — install from https://ollama.com
# =============================================================================


# =============================================================================
# PROVIDER 1: Anthropic (current default — paid)
# =============================================================================
#
# Models (fastest → most capable):
#   "claude-haiku-4-5-20251001"   cheapest, fast, good for large taxon lists
#   "claude-sonnet-4-6"           balanced — recommended for most use
#   "claude-opus-4-6"             most capable, slowest, most expensive
#
# Default model is claude-opus-4-6 when no closure is used.

taxa_in_data <- unique(occurrence_data$taxon_name)
prompt       <- build_habitat_prompt(taxa_in_data, habitat_scheme = NULL)

#### PROVIDER BLOCK ####

# Option A: default model
LLM_output <- prompt_api(prompt)

# Option B: specific model
my_fn      <- function(p, ...) call_anthropic_api(p, model = "claude-sonnet-4-6")
LLM_output <- prompt_api(prompt, llm_fn = my_fn)

# Option C: specific model + higher token limit (for wide habitat schemes)
my_fn      <- function(p, ...) call_anthropic_api(p, model = "claude-sonnet-4-6",
                                                    max_tokens = 5000L)
LLM_output <- prompt_api(prompt, llm_fn = my_fn)

#### END PROVIDER ####

habitat_lookup <- parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
)


# =============================================================================
# PROVIDER 2: Google Gemini (free tier available — recommended for testing)
# =============================================================================
#
# Setup: get a free key at https://aistudio.google.com/apikey
#        add GEMINI_API_KEY=your_key_here to ~/.Renviron
#
# Free-tier models (no credit card required):
#   "gemini-2.0-flash"       default — fast, capable, generous free limits
#   "gemini-2.5-flash"       newer, slightly more capable
#   "gemini-2.5-flash-lite"  fastest, lowest cost, lightest capability
#
# Rate limits on free tier: ~15 requests/minute, 1500 requests/day (Flash).
# For large taxon lists that produce many chunks, add pause_seconds = 5.

taxa_in_data <- c("Eucyclogobius newberryi","salmo trutta")
prompt       <- build_habitat_prompt(taxa_in_data, habitat_scheme = scheme)

#### PROVIDER BLOCK ####

# Option B: specific model
my_fn      <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash")
LLM_output <- prompt_api(prompt, llm_fn = my_fn)

# Option C: free tier with rate-limit pause (recommended for > 5 chunks)
my_fn      <- function(p, ...) call_gemini_api(p, model = "gemini-2.0-flash")
LLM_output <- prompt_api(prompt, llm_fn = my_fn, pause_seconds = 5)

#### END PROVIDER ####

habitat_lookup <- parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
)


# =============================================================================
# PROVIDER 3: OpenAI / ChatGPT (paid)
# =============================================================================
#
# Setup: get a key at https://platform.openai.com/api-keys
#        add OPENAI_API_KEY=sk-... to ~/.Renviron
#
# Models (fastest/cheapest → most capable):
#   "gpt-4o-mini"    default — cheap, fast, good for structured CSV output
#   "gpt-4o"         more capable, higher cost
#   "gpt-4.1"        latest flagship as of 2026

taxa_in_data <- unique(occurrence_data$taxon_name)
prompt       <- build_habitat_prompt(taxa_in_data, habitat_scheme = NULL)

#### PROVIDER BLOCK ####

# Option A: default model (gpt-4o-mini)
LLM_output <- prompt_api(prompt, llm_fn = call_openai_api)

# Option B: more capable model
my_fn      <- function(p, ...) call_openai_api(p, model = "gpt-4o")
LLM_output <- prompt_api(prompt, llm_fn = my_fn)

# Option C: higher token limit for wide habitat schemes
my_fn      <- function(p, ...) call_openai_api(p, model = "gpt-4o",
                                                 max_tokens = 5000L)
LLM_output <- prompt_api(prompt, llm_fn = my_fn)

#### END PROVIDER ####

habitat_lookup <- parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
)


# =============================================================================
# PROVIDER 4: Ollama — local models (completely free, no internet required)
# =============================================================================
#
# Setup (one time):
#   1. Install Ollama: https://ollama.com
#   2. In Terminal, pull a model:
#        ollama pull llama3.2         # good general-purpose default (~2GB)
#        ollama pull qwen2.5:14b      # stronger reasoning, more RAM needed (~9GB)
#        ollama pull gemma3:12b       # good structured output (~7GB)
#   3. Ollama starts automatically on macOS — no manual server start needed.
#   4. Confirm with: ollama list
#
# Apple Silicon (arm64) notes:
#   - Models run via Metal GPU acceleration — fast for 7B-14B parameter models
#   - RAM guidance: 7B needs ~6GB, 14B needs ~10GB, 32B needs ~20GB
#   - On a Mac with 16GB RAM, llama3.2 or qwen2.5:14b work well
#   - Response quality is lower than cloud APIs for the same task complexity
#
# Practical advice: Ollama works well for the cheap screening steps
# (screen_pdf_structure, build_scheme_prompt). For habitat assignment with
# many columns, a 14B+ model is recommended; smaller models may not reliably
# produce well-formed CSV.

taxa_in_data <- unique(occurrence_data$taxon_name)
prompt       <- build_habitat_prompt(taxa_in_data, habitat_scheme = NULL)

#### PROVIDER BLOCK ####

# Option A: default model (llama3.2 — must be pulled first)
LLM_output <- prompt_api(prompt, llm_fn = call_ollama_api)

# Option B: stronger model for better structured output
my_fn      <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b")
LLM_output <- prompt_api(prompt, llm_fn = my_fn)

# Option C: with longer pause between chunks (local models are slower)
my_fn      <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b")
LLM_output <- prompt_api(prompt, llm_fn = my_fn, pause_seconds = 0)
# (pause_seconds = 0 is fine for Ollama — no rate limits on local calls)

#### END PROVIDER ####

habitat_lookup <- parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
)


# =============================================================================
# PROVIDER 5: Manual submission (any web interface — Claude.ai, ChatGPT, etc.)
# =============================================================================
#
# Use when: no API key available, or you want to review/edit the prompt before
# submitting, or a paper requires human-in-the-loop validation.
#
# prompt_manual() writes prompt files to disk, pauses R, and prints instructions.
# After pasting the LLM response into the response file(s), press Enter in R.

taxa_in_data <- unique(occurrence_data$taxon_name)
prompt       <- build_habitat_prompt(taxa_in_data, habitat_scheme = NULL)

#### PROVIDER BLOCK ####

info       <- prompt_manual(prompt, out_dir = "habitat_assignment")
# R is now paused. Instructions are printed in the console:
#   1. Open the prompt file(s) listed
#   2. Paste into your LLM web interface
#   3. Copy the response into the response file(s)
#   4. Press Enter in R to continue
LLM_output <- read_llm_response(info$response_files)

#### END PROVIDER ####

habitat_lookup <- parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
)


# =============================================================================
# USING PROVIDERS FOR SCREEN_PDF_STRUCTURE (cheap screening step)
# =============================================================================
#
# screen_pdf_structure() also accepts llm_fn — it's a good place to use
# a free or local provider since it's a simple classification task.

pdf_content   <- extract_pdf_text("my_paper.pdf")

# Gemini (free) for the cheap screening step
pdf_structure <- screen_pdf_structure(pdf_content, llm_fn = call_gemini_api)

# Ollama for fully offline processing
pdf_structure <- screen_pdf_structure(pdf_content, llm_fn = call_ollama_api)

# Then use a more capable cloud model for the expensive extraction step
# (call_api_pdf supports any vision-capable provider: anthropic, gemini, openai, ollama)
raw_responses <- call_api_pdf(pdf_structure, build_pdf_extract_prompt(pdf_structure))


# =============================================================================
# MIXING PROVIDERS IN ONE WORKFLOW
# =============================================================================
#
# A practical cost-saving pattern: use the free Gemini tier for cheap steps,
# reserve Anthropic for the expensive vision-API extraction step.

# Step 1: cheap text-only screening — Gemini (free)
pdf_content   <- extract_pdf_text("my_paper.pdf")
pdf_structure <- screen_pdf_structure(pdf_content, llm_fn = call_gemini_api)

# Step 2: cheap habitat scheme generation — Gemini (free)
sp     <- build_scheme_prompt(taxa_in_data, realm = "marine")
raw_s  <- prompt_api(sp, llm_fn = call_gemini_api)
scheme <- parse_scheme_response(raw_s, sp)

# Step 3: habitat assignment — Gemini (free) or Anthropic if quality insufficient
prompt     <- build_habitat_prompt(taxa_in_data, habitat_scheme = scheme)
LLM_output <- prompt_api(prompt, llm_fn = call_gemini_api)

# Step 4: PDF extraction — Anthropic only (vision API)
extract_prompt <- build_pdf_extract_prompt(pdf_structure)
raw_response   <- call_api_pdf(pdf_structure, extract_prompt)
occurrences    <- parse_pdf_extract_response(raw_response, pdf_structure)
