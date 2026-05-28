# TaxaTools Session Notes Archive
# Sessions 27–84. Current sessions live in TaxaTools/CLAUDE.md.

**Session 27 (2026-03-26)**
- Tests written for `clean_taxon_names`, `create_taxon_names`, `change_backbone` — all pass
- Bug fixed in `clean_taxon_names`: bracket stripping (`[Bacillus] subtilis`) now happens
  before the capital-letter filter; previously bracketed names were silently dropped
- `NA_character_` required (not `NA`) when testing character-vector functions
- CLAUDE.md restructured: ecosystem context moved to `TaxaID/CLAUDE.md`; this file is package-specific

**Session 28 (2026-03-26)**
- LLM provider functions moved from TaxaFetch → TaxaTools/R/llm_api_utils.R
  (`call_anthropic_api`, `call_gemini_api`, `call_openai_api`, `call_ollama_api`,
  `prompt_api`, `prompt_manual`, `read_llm_response`)
- TaxaHabitat package created; habitat assignment functions moved from TaxaFetch
- `httr2` added to DESCRIPTION Imports
- TODO: Run `devtools::document()` and `devtools::check()` on TaxaTools

  # Lafferty removed "unique(cleaned)" from last line of clean_taxon_names!!! 29 March 2026

**Session 52 (2026-04-09)**
- `clean_taxon_names()` output now length-preserving (invalid → NA, duplicates kept)
- `attr(result, "model")` added to all 4 LLM provider returns
- `inst/CITATION` created

**Session 55 (2026-04-12)**
- `build_report_context()`, `draft_methods_text()`, `draft_results_text()` added to R/draft_text.R
- General-purpose LLM text generation: read code → methods prose, read R objects → results prose
- `build_report_context()` creates domain-agnostic S3 `report_context` object with verified facts
- Methods prompt includes statistics bleed guard (statistics shown for accuracy only, not to be reported)
- Both prompts include LLM caution instructions (flag LLM-derived data, stochastic output caveat)
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 57 (2026-04-15) — Prompts 14-16**
- `R/rank_utils.R` created: exports `standard_ranks`, `extended_ranks`, `detect_ranks()`
  (Prompt 14). Replaces inline rank definitions across downstream packages.
- `R/find_taxonomy_conflicts.R` created: exports `find_taxonomy_conflicts()` (Prompt 15, GITA G8).
  Detects higher-rank inconsistencies; returns conflict data frame.
- `R/is_valid_species_name.R` created: exports `is_valid_species_name()` (Prompt 16, D3).
  Consolidated from internal copies in TaxaLikely + TaxaAssign.
- `R/barcode_utils.R` created: exports `barcode_length_defaults` + `resolve_barcode_lengths()`
  (Prompt 16, D4). Consolidated from 3 internal copies across TaxaLikely, TaxaMatch, TaxaAssign.
- `%||%` in `R/llm_api_utils.R` upgraded from `@noRd` to `@export` with `@name null-coalesce`
  (Prompt 16, D2). Downstream packages import via `@importFrom TaxaTools %||%`.
- Empty `utils::globalVariables(character(0))` removed from files with no NSE references.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 77 (2026-05-19)**
- `R/census_genus_species.R` created: exports `census_genus_species()`.
  Queries GBIF backbone via `rgbif::name_usage(key, data="children")` to enumerate
  all described species within each genus. `match_species` param computes per-genus
  completeness (complete / singleton_missing / incomplete). Higher-rank recursion
  (family → genera → species) via `.census_higher_rank()` and `.fetch_children_genera()`.
- `rgbif` added to Suggests in DESCRIPTION.
- Character key coercion: `name_backbone()` returns character usageKeys; the function
  now accepts and coerces character vectors to numeric.
- 41 tests in `test-census_genus_species.R` (all mocked GBIF responses for offline testing).
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 79 (2026-05-20)**
- No TaxaTools-specific changes. `sample_id` → `observation_id` ecosystem rename did not
  affect TaxaTools (package does not use that column).

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `.onAttach()` added to `R/zzz.R`: scans env vars for API keys on `library(TaxaTools)`;
  sets `options(TaxaID.llm_fn)`. Priority: Anthropic > Gemini > OpenAI > Azure.
  0 keys → setup message; 1 key → auto-set; 2+ keys → auto-select + how to switch.
- `options(TaxaID.llm_fn)` new ecosystem-wide R option; all `llm_fn` defaults updated to
  `getOption("TaxaID.llm_fn", call_anthropic_api)` in `prompt_api()`, `draft_methods_text()`,
  `draft_results_text()`.
- `rank_system` default NULL in `create_taxon_names()`; auto-detects via `detect_ranks()`.

**Session 83 (2026-05-21)**
- `R/model_registry.R` created: `list_models()`, `refresh_models()`, `set_model()`,
  `model_cache_info()`. Tier patterns (fast/mid/top) in `inst/model_tiers.json`;
  provider `/models` endpoints queried live and cached in `~/.cache/R/TaxaTools/model_cache.json`.
- `call_azure_api()` added: Azure OpenAI provider for DOI employees; default endpoint
  `api-dev.ai.doi.net`; `AZURE_OPENAI_API_KEY` env var.
- `inst/test_api_keys.R` added: standalone script to validate all configured API keys.
- `model = NULL` + `tier` param added to all 5 `call_*_api()` functions.

**Session 84 (2026-05-22)**
- `base_url` param added to `call_openai_api()`: enables any OpenAI-compatible API
  (Grok/xAI, Groq, Mistral, etc.) via base URL swap. Default unchanged.
- `register_provider()` added: session-only registration of custom OpenAI-compatible
  providers. Registered providers appear in `list_models()`, `refresh_models()`,
  `set_model()`, and trigger automatic tier resolution in `call_openai_api()`.
