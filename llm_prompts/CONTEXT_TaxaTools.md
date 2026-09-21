# CONTEXT: TaxaTools

**Uploads, standardizes and corrects taxonomy across backbones**

Provides helper functions for cleaning, verifying, and standardizing taxonomic names across multiple backbones. Capabilities include spell-checking and correcting species names, translating names between taxonomic backbones (e.g., GBIF, NCBI, WoRMS), retrieving classification hierarchies via API, and creating standardized taxon labels at any rank. Also provides LLM provider functions for calling Anthropic, OpenAI, Gemini, and Ollama APIs, and LLM-assisted text generation for drafting methods and results sections. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-20 21:09:22 UTC; unix). 52 exported function(s).

## Functions

### %||%(x, y)

Null-coalescing operator

Returns 'x' if it is non-'NULL' and has length > 0; otherwise returns 'y'. Defined once in TaxaTools; downstream packages import via @importFrom TaxaTools %||%.

| Param | Required | Default | Doc |
|---|---|---|---|
| x | yes |  | Values to coalesce. |
| y | yes |  | Values to coalesce. |

**Value:** 'x' when non-'NULL' and 'length(x) > 0', otherwise 'y'.

### assemble_report(..., title = NULL, study_description = NULL)

Assemble Multiple Report Sections into a Unified Report

Takes any number of 'report_section' objects (typically one per TaxaID package used in a pipeline) and assembles them into a single markdown document. Sections are ordered by their position in the standard TaxaID pipeline. Citations are deduplicated and collected into a single "Data Sources" section at the end.

| Param | Required | Default | Doc |
|---|---|---|---|
| ... | yes |  | report_section objects, in any order. |
| title | no | NULL | Character or NULL. Optional report title. |
| study_description | no | NULL | Character or NULL. Optional study description paragraph inserted before the Methods sections. |

**Value:** A length-1 character string containing the full assembled markdown report. Pass to 'writeLines()' to write to a file, or to 'cat()' to view in the console: writeLines(full_report, "methods_report.md")

### assign_sampling_group(taxonomy, scheme = default_sampling_scheme(), rank_cols = c("kingdom", "phylum", "class", "order"), kingdom_guard = TRUE, harmonise = FALSE, backbone_id = 11L, cache_dir = NULL, verbose = TRUE)

Assign Sampling Groups from Taxonomic Rank Columns

Classifies each row of a taxonomy table into a 'sampling_group' (the shared-effort denominator, kernel-fit group, and dark-diversity-floor group used throughout the TaxaID ecosystem) using an ordered, first-match-wins rule scheme - see 'default_sampling_scheme'. This is the single package-level home for logic that was previously an inline 'dplyr::case_when()' duplicated across five workflow files, and had silently drifted three times before this fix (see 'default_sampling_scheme''s Details).

| Param | Required | Default | Doc |
|---|---|---|---|
| taxonomy | yes |  | A data frame (or tibble) with at least some of the columns named in rank_cols. Returned as-is with a new sampling_group column added. |
| scheme | no | default_sampling_scheme() | A sampling-group scheme object; see default_sampling_scheme for the required shape. Supply a custom scheme (e.g. default_sampling_scheme() with an appended or edited rule) to override the default classification -- the whole rules/catch_all/kingdom_guard_vocabulary object is used exactly as supplied, with no merging against the default. |
| rank_cols | no | c("kingdom", "phylum", "class", "order") | Character vector of taxonomic rank columns to read, in COARSE-TO-FINE order. Default c("kingdom", "phylum", "class", "order") -- the four ranks every rule in default_sampling_scheme() reads. A column absent from taxonomy is treated as entirely NA (never an error), so a taxonomy table missing e.g. order still classifies on the ranks it does have. |
| kingdom_guard | no | TRUE | Logical, default TRUE. When a row reaches the catch-all (scheme$catch_all, normally "macroinvertebrates") and its kingdom is NOT one of scheme$kingdom_guard_vocabulary (default c("Animalia", "Metazoa")), the row's sampling_group is set to NA instead of the catch-all. This is the single mechanism that closes the open-ended protist tail: rather than enumerating every non-animal class GBIF's backbone might ever produce (Heliozoa, Amoebozoa, Ascomycota, Chytridiomycota, Foraminifera, ... -- an unbounded and ever-growing list), any row whose kingdom is not plausibly an animal is refused the animal-flavoured catch-all ("macroinvertebrates" literally means "not a vertebrate ANIMAL") and surfaced as NA instead, where it is visible to a caller auditing unmatched rows rather than silently, indefinitely counted as a benthic invertebrate. The guard deliberately does NOT fire on a row with a NA (missing) kingdom -- a row with no usable taxonomy at all is a different problem (it may be genuinely novel), not something this function should silently discard. Set kingdom_guard = FALSE to restore the old case_when() behaviour, where every unmatched row (any kingdom, including NA) becomes the catch-all. |
| harmonise | no | FALSE | Logical, default FALSE. When TRUE, taxonomy is harmonised to scheme's backbone BEFORE classification, via verify_taxon_names(backbone_id = backbone_id) -> change_backbone() -- the same idiom CaliforniaIntertidal/scope_classifier.R's harmonize_ranks_to_gbif() documents, and the one PtConceptionWorkflow_18S_2_single_site.R already uses to fold in an NCBI-backbone dataset. This lets an NCBI-backbone match object (e.g. one carrying class = "Copepoda", class = "Thalassiosirophyceae", or kingdom "Chromista"/"Protozoa" in vocabulary the default scheme does not otherwise recognise) be classified correctly against a GBIF-vocabulary scheme, at a real cost: one backbone name-verification lookup per unique value at the finest available rank in rank_cols (so, typically, one call per unique order value -- cheap relative to a per-species lookup, but not free, and it is a live API call unless cache_dir serves it from a prior run). harmonise is OFF by default specifically because of this cost -- most callers already have GBIF-vocabulary taxonomy and gain nothing from paying it. A rank name that fails to resolve keeps its ORIGINAL value rather than becoming NA (matches the source and never silently loses taxonomy), and so does one the backbone resolves at the WRONG RANK -- see the Rank agreement section, which is what stops a homonym at another rank from overwriting the row's whole lineage. |
| backbone_id | no | 11L | Integer backbone ID passed to verify_taxon_names when harmonise = TRUE. Default 11L (GBIF), matching default_sampling_scheme()'s own vocabulary. Ignored when harmonise = FALSE. |
| cache_dir | no | NULL | Optional directory for a persistent, content-keyed cache of the harmonisation lookup (one .rds file, keyed on the sorted unique rank names actually resolved) -- only used, and only relevant, when harmonise = TRUE. NULL (default) does no caching, so every call re-resolves every unique name. |
| verbose | no | TRUE | Logical, default TRUE. Print one table of the resulting sampling_group counts (including the NA count) after classification, and progress messages during harmonisation. |

**Value:** 'taxonomy' (or its harmonised copy, when 'harmonise = TRUE') with a new 'sampling_group' character column added. 'NA' where no rule matched AND the kingdom guard fired; otherwise always one of the group names in 'scheme$rules' or 'scheme$catch_all'.

### build_report_context(study_description = NULL, data_type = NULL, workflow = NULL, packages = NULL, parameters = NULL, statistics = NULL, citations = NULL, facts = NULL)

Build a Report Context Object

Creates a structured context object containing grounded facts about an analysis. When passed to 'draft_methods_text' or 'draft_results_text', these facts are injected into the LLM prompt so the model uses verified information rather than inferring from code comments or data summaries.

| Param | Required | Default | Doc |
|---|---|---|---|
| study_description | no | NULL | Character. One or two sentences describing the study (e.g., "eDNA metabarcoding of coral reef fish at Palmyra Atoll", or "Phase III clinical trial of drug X in 500 patients"). Default NULL. |
| data_type | no | NULL | Character. Type of data (e.g., "eDNA", "survey", "time series", "spatial", "experimental"). Default NULL. |
| workflow | no | NULL | Character. Analysis pipeline or approach (e.g., "Bayesian likelihood model", "mixed-effects regression", "machine learning classification"). Default NULL. |
| packages | no | NULL | Character vector. Software packages used, with optional version info (e.g., c("lme4 1.1-35", "ggplot2", "dplyr")). Default NULL. |
| parameters | no | NULL | Named list. Key analysis parameters and their values (e.g., list(alpha = 0.05, n_iterations = 1000, min_score = 70)). Default NULL. |
| statistics | no | NULL | Named list. Summary statistics to report as verified facts (e.g., list(n_samples = 70, n_resolved = 65, resolution_rate = 92.9, mean_effect_size = 0.45)). Default NULL. |
| citations | no | NULL | Character vector. References to incorporate into the text (e.g., c("Callahan et al. (2016) DADA2", "R Core Team (2025)")). Default NULL. |
| facts | no | NULL | Named list. Domain-specific grounding facts as key-value pairs. Use this for any information that does not fit the other fields (e.g., list(location = "Palmyra Atoll", marker = "12S MiFish", sampling_year = 2017, model_type = "VAR(2)")). Default NULL. |

**Value:** An S3 object of class '"report_context"' (a named list).

### cache_ok(path, inputs = NULL)

Is a cache file usable, given the inputs it derives from?

A cache gate that tests only 'file.exists()' silently serves stale results. This is the ecosystem's staleness primitive: a cache is usable only if it exists AND is not older than any of the artifacts it was derived from.

| Param | Required | Default | Doc |
|---|---|---|---|
| path | yes |  | Character. Path to the candidate cache file. |
| inputs | no | NULL | Character vector or NULL. Paths this cache was derived FROM. Missing and NA entries are ignored, so a caller can pass an optional upstream without branching. If any surviving input is newer than path, the cache is rejected. |

**Value:** 'TRUE' if 'path' exists and no declared input is newer; 'FALSE' otherwise. Rejection emits a message naming the culprit.

### call_anthropic_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), max_tokens = 3000L, api_key = Sys.getenv("ANTHROPIC_API_KEY"))

Call the Anthropic API with a Single Prompt String

Low-level generic function: submits one plain character string to the Anthropic Messages API and returns the model's response as a plain character string. No chunking, no S3 class requirements, no domain-specific logic. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Exact Anthropic model identifier, e.g. "claude-sonnet-4-6". Default NULL resolves to the latest model for tier via list_models. Specify an exact model to pin a version for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast" (cheapest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. |
| max_tokens | no | 3000L | Integer. Maximum tokens in the response (default 3000). Sufficient for most taxonomy and habitat prompts. Increase for longer outputs (e.g., large species lists). Higher values increase API cost. |
| api_key | no | Sys.getenv("ANTHROPIC_API_KEY") | Character. Anthropic API key. Defaults to the ANTHROPIC_API_KEY environment variable. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status.

### call_api(prompt_str, provider = NULL, tier = c("mid", "fast", "top"), model = NULL, max_tokens = 3000L, api_key = NULL, base_url = NULL, images = NULL, show_tokens = FALSE, max_input_tokens = NULL, timeout = 120)

Call Any Configured LLM with a Single Prompt String

Generic provider-neutral function. Resolves the provider, model, API key, and endpoint from the registry ('inst/model_tiers.json' plus any session entries added via 'register_provider'), builds the provider-appropriate HTTP request, and returns the model's response as a plain character string.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| provider | no | NULL | Character. Provider name: "anthropic", "gemini", "openai", "azure_openai", "ollama", or any name registered with register_provider. Default NULL uses options("TaxaID.provider"), which is set automatically by library(TaxaTools) based on detected API keys. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier when model = NULL: "fast" (cheapest/smallest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. Tier-to-model mapping is discovered live from the provider's /models endpoint (see list_models). |
| model | no | NULL | Character. Exact model identifier. Overrides tier resolution. Use to pin a specific version for reproducibility. |
| max_tokens | no | 3000L | Integer. Maximum tokens in the response (default 3000). The correct request body field for the provider (max_tokens vs max_completion_tokens) is read from the registry automatically. |
| api_key | no | NULL | Character. API key override. Default NULL reads the key from the environment variable named in the provider's registry entry (e.g. ANTHROPIC_API_KEY). Keyless providers (Ollama) ignore this. |
| base_url | no | NULL | Character. Base URL override for OpenAI-compatible providers (OpenAI, Azure, Ollama, custom registered providers). Default NULL uses the provider's registered endpoint. For Ollama: change the host/port, e.g. base_url = "http://remote-server:11434". For OpenAI-compatible proxies: supply the proxy base URL. For Azure: replaces the host in the endpoint template while preserving the deployment path and API version. |
| images | no | NULL | Named list of base64-encoded PNG strings, as returned by .render_pdf_pages() in the TaxaFetch PDF pipeline. Default NULL (text-only call). When supplied, the prompt and images are sent as a multi-modal message using the provider's vision format: Anthropic image content blocks, Gemini inlineData parts, or OpenAI image_url blocks. Requires a vision-capable model (e.g. Claude Sonnet, Gemini 2.5 Flash, GPT-4o). |
| show_tokens | no | FALSE | Logical. When TRUE, prints a message after each call reporting the provider, model, and token counts (e.g. "Tokens used [anthropic / claude-sonnet-4-6] — input: 312, output: 87"). Default FALSE to avoid output in non-interactive workflows. Token counts are retrieved from the provider's response body; NA is reported when a provider does not return usage information. |
| max_input_tokens | no | NULL | Integer or NULL. When non-NULL, estimates the prompt length as ceiling(nchar(prompt_str) / 3.5) (a conservative characters-per-token heuristic) and stops with an informative error before making the HTTP request if the estimate exceeds the limit. Use this as a pre-flight guard against accidentally sending very large prompts. Default NULL (no check performed). |
| timeout | no | 120 | Numeric. Request timeout in seconds, passed to httr2::req_timeout(). Default 120. Raise this for a slow provider/model (e.g. a large local Ollama model) or a large multi-image PDF-vision call that can legitimately take longer than two minutes. |

**Value:** A length-1 character string containing the model's response text. The following attributes are attached: '"model"' The resolved model identifier. '"provider"' The provider name used. '"tokens"' A named list with elements 'input' and 'output' (integers) giving the token counts reported by the provider. Both are 'NA_integer_' when the provider does not return usage information. Stops on any ...

### call_azure_openai_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), endpoint = NULL, max_completion_tokens = 3000L, api_key = Sys.getenv("AZURE_OPENAI_API_KEY"))

Call the Azure OpenAI API with a Single Prompt String

Low-level provider function: submits one plain character string to an Azure OpenAI Chat Completions endpoint and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Azure deployment name, e.g. "gpt-5.1". Default NULL resolves to the latest available deployment for tier via list_models. Specify an exact name to pin for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast", "mid" (default), or "top". For Azure, all tiers currently map to the same DOI deployment; the param is accepted for interface consistency. |
| endpoint | no | NULL | Character. Full deployment URL override (backward-compatible escape hatch). When provided, the deployment name is extracted from the URL path and the host is used to override the default DOI endpoint. Default NULL builds the URL from the registry template and the resolved model name. |
| max_completion_tokens | no | 3000L | Integer. Maximum tokens in the response (default 3000). Azure o-series models use this field name instead of max_tokens; handled automatically via the registry. |
| api_key | no | Sys.getenv("AZURE_OPENAI_API_KEY") | Character. Azure OpenAI API key. Defaults to the AZURE_OPENAI_API_KEY environment variable. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status.

### call_gemini_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), max_tokens = 3000L, api_key = Sys.getenv("GEMINI_API_KEY"))

Call the Google Gemini API with a Single Prompt String

Low-level provider function: submits one plain character string to the Google Gemini generateContent API and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Exact Gemini model identifier, e.g. "gemini-2.5-flash". Default NULL resolves to the latest model for tier via list_models. Specify an exact model to pin a version for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast" (cheapest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. |
| max_tokens | no | 3000L | Integer. Maximum tokens in the response (default 3000). Sufficient for most taxonomy and habitat prompts. Increase for longer outputs (e.g., large species lists). Higher values increase API cost. |
| api_key | no | Sys.getenv("GEMINI_API_KEY") | Character. Google AI Studio API key. Defaults to the GEMINI_API_KEY environment variable. Get a free key at https://aistudio.google.com/apikey and add GEMINI_API_KEY=AIza... to ~/.Renviron. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status or safety block.

### call_ollama_api(prompt_str, model = "llama3.2", max_tokens = 3000L, base_url = "http://localhost:11434")

Call a Local Ollama Model with a Single Prompt String

Low-level provider function: submits one plain character string to a locally running Ollama instance and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Completely free - no API key or internet connection required after model download. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | "llama3.2" | Character. Ollama model name as listed by ollama list in Terminal. Default "llama3.2". Pull a model before first use: ollama pull llama3.2. Browse available models at https://ollama.com/library. Capable options for Apple Silicon: "llama3.1:8b", "mistral", "gemma3:12b", "qwen2.5:14b". |
| max_tokens | no | 3000L | Integer. Maximum tokens in the response (default 3000). Behaviour is model-dependent; some models may ignore this setting. |
| base_url | no | "http://localhost:11434" | Character. Base URL of the Ollama server. Default "http://localhost:11434". Change only if running Ollama on a different host or port. |

**Value:** A length-1 character string containing the model's response text. Stops with a clear message if Ollama is not running or the model has not been pulled.

### call_openai_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), max_tokens = 3000L, base_url = "https://api.openai.com", api_key = Sys.getenv("OPENAI_API_KEY"))

Call the OpenAI Chat Completions API with a Single Prompt String

Low-level provider function: submits one plain character string to the OpenAI Chat Completions API and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Exact OpenAI model identifier, e.g. "gpt-4o-mini". Default NULL resolves to the latest model for tier via list_models. Specify an exact model to pin a version for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast" (cheapest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. |
| max_tokens | no | 3000L | Integer. Maximum tokens in the response (default 3000). Sufficient for most taxonomy and habitat prompts. Increase for longer outputs (e.g., large species lists). Higher values increase API cost. |
| base_url | no | "https://api.openai.com" | Character. Base URL of the API endpoint. Default "https://api.openai.com" (OpenAI). Any OpenAI-compatible API can be used by changing this URL -- see Details. When using a non-default URL, register the provider with register_provider to enable automatic tier resolution, or specify model explicitly. |
| api_key | no | Sys.getenv("OPENAI_API_KEY") | Character. API key for the provider. Defaults to the OPENAI_API_KEY environment variable for the standard OpenAI endpoint. For alternative providers, pass the key directly or via Sys.getenv("MY_KEY_VAR") in a closure. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status.

### census_genus_species(genus_keys, match_species = NULL, rank = "genus", status_filter = "ACCEPTED", verbose = TRUE)

Census described species within genera (or higher ranks) via GBIF backbone

Queries the GBIF backbone taxonomy to enumerate all described species within each queried taxon. Optionally compares against a reference species list (e.g., from a match object) to classify genera by completeness.

| Param | Required | Default | Doc |
|---|---|---|---|
| genus_keys | yes |  | Named integer vector: names are taxon names (e.g., genus names), values are GBIF usageKeys. Obtain from GBIF occurrence data (genusKey column) or from rgbif::name_backbone(). |
| match_species | no | NULL | Character vector of species already in the reference database (e.g., unique(match_df$species)). If provided, the function computes per-genus completeness: how many described species are missing from the reference. If NULL (default), only the GBIF census is returned without reference comparison. |
| rank | no | "genus" | Character string indicating the rank of the input keys. Default "genus". For higher ranks (e.g., "family", "order"), the function recursively enumerates child genera, then species within each genus. |
| status_filter | no | "ACCEPTED" | Character vector of GBIF taxonomicStatus values to include. Default "ACCEPTED". Set to c("ACCEPTED", "DOUBTFUL") to include taxonomically uncertain species. |
| verbose | no | TRUE | Logical. If TRUE (default), prints progress messages. |

**Value:** A data frame with one row per queried taxon (genus or higher rank): group Character. Taxon name (genus/family/order). gbif_key Integer. GBIF usageKey used for the query. total_described Integer. Number of accepted species in GBIF backbone. in_reference Integer. Species found in 'match_species' (NA if 'match_species' not provided). n_missing Integer. 'total_described - in_reference' (NA if ...

### change_backbone(input_df, input_col, old_backbone_label = "source_name", new_backbone_label = "translated_name", keep_unmatched = TRUE)

Translate Taxon Names Between Taxonomic Backbones

Post-processes the output of 'verify_taxon_names' to (1) rename the source and translated name columns with meaningful backbone labels, and (2) parse the pipe-delimited 'classification_path' and 'classification_ranks' columns into a wide-format taxonomy table (one column per rank: kingdom, phylum, class, etc.).

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A dataframe returned by verify_taxon_names, containing at minimum: user_supplied_name, matched_name, classification_path, and classification_ranks. |
| input_col | yes |  | Character. The name of the column in input_df holding the original (source backbone) names. Typically "user_supplied_name". |
| old_backbone_label | no | "source_name" | Character. The label to assign to the source-name column in the output (e.g., "NCBI" or "GBIF"). Default is "source_name". |
| new_backbone_label | no | "translated_name" | Character. The label to assign to the translated-name column in the output (e.g., "GBIF" or "NCBI"). Default is "translated_name". |
| keep_unmatched | no | TRUE | Logical. When TRUE (the default), names for which the target backbone returns no match are retained by copying the original source name into the translated-name column rather than leaving it NA. Set to FALSE to keep NA for unmatched names (original behaviour). |

**Value:** A dataframe with: '<old_backbone_label>' Original names (renamed from 'input_col'). '<new_backbone_label>' Translated names (renamed from 'matched_name'). 'backbone_matched' Logical. 'TRUE' when the target backbone returned a genuine match; 'FALSE' when no match was found (the source name was retained due to 'keep_unmatched = TRUE', or left 'NA' when 'keep_unmatched = FALSE'). Always 'TRUE' ...

### check_taxaid_manifest(path, packages = NULL, on_mismatch = c("error", "warning", "message", "silent"))

Check the Installed TaxaID Code Against a Recorded Manifest

Compares the library this session is using against a manifest written by 'write_taxaid_manifest()', and by default *errors* on any difference. Put it in a workflow preamble so drift stops a run at the top rather than producing results nobody can attribute afterwards.

| Param | Required | Default | Doc |
|---|---|---|---|
| path | yes |  | Path to a manifest written by write_taxaid_manifest(). |
| packages | no | NULL | Restrict the comparison. Default: every package named in the manifest or in the standard TaxaID set. |
| on_mismatch | no | c("error", "warning", "message", "silent") | One of "error" (default), "warning", "message", "silent". |

**Value:** Invisibly, a list with 'ok', 'missing', 'changed', 'extra' and 'manifest' (the freshly built one).

### clean_taxon_names(name_vec, remove_abbr = NULL, strip_modifiers = NULL)

Extract and Clean Taxon Names from a Character Vector

Cleans a character vector of taxon names by normalising whitespace, removing 'NA's, removing names that do not begin with a capital letter (e.g., codes, placeholders, artefacts), converting underscore-separated binomials to space-separated ones (e.g. '"Corallina_officinalis"' -> '"Corallina officinalis"', as produced by Jonah Ventures and SILVA pipelines), trimming abbreviated second words (sp., spp., etc.) to genus-only, stripping bracket artefacts, and stripping a single known leading breeding/ploidy-manipulation modifier word (e.g. '"androgenetic Carassius auratus"' -> '"Carassius ...

| Param | Required | Default | Doc |
|---|---|---|---|
| name_vec | yes |  | A character vector (or factor) of taxon names. |
| remove_abbr | no | NULL | A character vector of second-word tokens that flag the name as genus-only (the abbreviation is dropped). Defaults to a standard list of common abbreviations and placeholder terms. Pass a custom vector to extend or replace the default list. |
| strip_modifiers | no | NULL | A character vector of known leading modifier words (case-insensitive, matched against the FIRST whitespace-delimited token only, and only ever removed once per name -- never a repeated strip). Defaults to a curated list of real breeding/ploidy-manipulation terms found on real GenBank hybrid-cross records ("androgenetic", "gynogenetic", "autodiploid", "autotriploid", "autotetraploid", "allodiploid", "allotriploid", "allotetraploid", "diploid", "triploid", "tetraploid", "polyploid"). Deliberately does NOT include uncertainty-hedge words ("possible", "putative", "probable", "tentative", "presumed", etc.) or "hybrid"/"unidentified" themselves -- those genuinely change what the name means (a hedge should keep failing the capital- letter filter below, not get silently rescued into a confident binomial; "hybrid X x Y" with no named first parent has no real maternal-parent identity to recover). Pass a custom vector to extend or replace the default list; character(0) disables this step entirely (restores this function's pre-2026-08-11 behavior). |

**Value:** A character vector the same length as 'name_vec'. Names that do not start with a capital letter, are 'NA', or consist only of an abbreviation are set to 'NA'. An R attribute 'collapsed_to_genus' (logical, same length) is also set: 'TRUE' for a row that HAD a real second token (an epithet-shaped string, e.g. an open-nomenclature label like '"Ictalurus cf. pricei USON-01120-1"') which was ...

### common_to_scientific(common_names, taxon_group = NULL, location = NULL, backbone_id = 11L, verify = TRUE, llm_fn = getOption("TaxaID.llm_fn"), ...)

Convert Common Names to Scientific Names

Uses a large language model (LLM) to convert a character vector of common names to scientific names, optionally narrowing the search with a taxonomic group and geographic location. When 'verify = TRUE' (default), each LLM-suggested scientific name is checked against the specified taxonomic backbone via 'verify_taxon_names', guarding against hallucination.

| Param | Required | Default | Doc |
|---|---|---|---|
| common_names | yes |  | Character vector of common names to look up. |
| taxon_group | no | NULL | Character string narrowing the taxonomic search scope (e.g., "birds", "freshwater fish", "mammals"). Strongly recommended when names could apply to multiple groups. Default NULL. |
| location | no | NULL | Character string providing geographic context for regionally ambiguous names (e.g., "Pacific Northwest, USA", "United Kingdom"). Default NULL. |
| backbone_id | no | 11L | Integer. Taxonomic backbone for verification. 11 = GBIF (default), 3 = ITIS, 4 = NCBI, 9 = WoRMS, 1 = Catalogue of Life. |
| verify | no | TRUE | Logical. If TRUE (default), runs verify_taxon_names on each non-NA LLM suggestion and populates scientific_name_verified and verified. |
| llm_fn | no | getOption("TaxaID.llm_fn") | Function with signature function(prompt, ...) -> character(1). Default getOption("TaxaID.llm_fn"). |
| ... | yes |  | Additional arguments passed to llm_fn. |

**Value:** A data frame with one row per element of 'common_names': 'common_name' Input common name (character). 'scientific_name_llm' Scientific name suggested by the LLM, or 'NA' if ambiguous or unknown. 'scientific_name_verified' Backbone-verified scientific name (from 'verify_taxon_names'), or 'NA' if verification failed or 'verify = FALSE'. 'backbone_id' Backbone used for verification (integer). ...

### create_taxon_names(input_df, rank_system = NULL)

Create Most Specific Taxon Name Column

Takes a dataframe with separate taxonomic rank columns and adds two new columns: 'taxon_name' (the value from the most specific non-NA rank) and 'taxon_name_rank' (the name of that rank, in lowercase). Column matching is case-insensitive, so rank columns named "Kingdom" or "KINGDOM" match the same as "kingdom".

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A data frame containing taxonomic rank columns. |
| rank_system | no | NULL | A character vector of column names (any case) listing taxonomic ranks from broadest to most specific, e.g. c("kingdom", "phylum", "class", "order", "family", "genus", "species"). The function walks this vector from right to left and returns the first non-empty value. If NULL (the default), auto-detected from column names via detect_ranks. |

**Value:** The input data frame with two columns appended: taxon_name The most specific non-NA rank value for each row. taxon_name_rank The rank label (lowercase) corresponding to 'taxon_name'. 'NA' when all ranks are 'NA'.

### default_sampling_scheme()

Default Sampling-Group Classification Scheme

Returns the package's default sampling-group scheme: an ORDERED list of rules (first-match-wins, exactly like the 'dplyr::case_when()' it replaces) that classifies a taxon's kingdom/phylum/class/order into one of eleven detection-process groups, or a catch-all. Ported clause-for-clause from 'PtConceptionWorkflow_18S_2_single_site.R''s Step 4 (the fullest, best-commented inline version of this classifier), with two 2026-09-13 additions (see Details).

(no parameters)

**Value:** A sampling-group scheme object; see Shape above.

### define_search_polygon(lat = NULL, lon = NULL, radius_deg = NULL, tile = "Esri.OceanBasemap", points = NULL, group_col = NULL, init_polygon = NULL, title = "Define Search Polygon", done_label = "Done", cancel_label = "Cancel", viewer = shiny::paneViewer(minHeight = 500))

Define a Search Polygon Interactively

Opens an interactive Shiny gadget centred on a given point (or on a previously drawn polygon, via 'init_polygon'). The initial shape is a square with four draggable corner markers (or the reopened polygon's own vertices). Drag any marker to reshape the polygon. Use *Add Point* to insert a new vertex at the midpoint of the longest side (then drag it into place); use *Remove Last Point* to undo the most recent addition. Click *Done* to return the polygon as a WKT string ready to pass to 'download_gbif_occurrences' or 'fetch_gbif_occurrences'.

| Param | Required | Default | Doc |
|---|---|---|---|
| lat | no | NULL | Numeric. Latitude of the centre point in decimal degrees (WGS 84). Ignored when init_polygon is supplied (the centre is derived from the polygon instead). Required otherwise. |
| lon | no | NULL | Numeric. Longitude of the centre point in decimal degrees (WGS 84). Ignored when init_polygon is supplied. Required otherwise. |
| radius_deg | no | NULL | Numeric. Half-width of the initial square in decimal degrees. For reference: 1 degree ~= 111 km. Ignored when init_polygon is supplied. Required otherwise. |
| tile | no | "Esri.OceanBasemap" | Character. Leaflet tile provider name. Default "Esri.OceanBasemap". Any string accepted by leaflet::addProviderTiles() works (e.g. "OpenStreetMap", "Esri.WorldImagery"). |
| points | no | NULL | Data frame of observation coordinates to overlay on the map as small, non-interactive reference markers (does not affect the returned polygon). Must have lat and lng columns. Useful for seeing the actual data cloud while drawing a group or search-area boundary around it. Default NULL (no overlay). |
| group_col | no | NULL | Character. Optional column name in points used to color the reference markers by group (e.g. an already-assigned spatial_group_id), with a legend. Lets a user drawing a broader search area see which points already belong to which group. Default NULL (all markers drawn in one flat color). |
| init_polygon | no | NULL | Character. An existing WKT POLYGON string (as returned by a previous call to this function) to reopen for editing, instead of starting from a fresh square. Its own vertices become the initial draggable markers. When supplied, lat/lon/ radius_deg are not required and are ignored if given. |
| title | no | "Define Search Polygon" | Character. Gadget title bar text. Default "Define Search Polygon". Callers embedding this gadget in a larger workflow (e.g. group_observations_by_bbox) should pass something identifying what this particular call is for (e.g. which spatial group or search area is being drawn) -- session experience showed that information buried only in a console message is easy to miss while looking at the map itself. |
| done_label | no | "Done" | Character. Label for the primary (right-hand) title bar button. Default "Done". Override with a verb describing what clicking it actually does in the calling context (e.g. "Group These Points") -- generic "Done" reads as "confirm and proceed," which does not by itself convey that clicking it before resizing the initial square will capture everything currently visible. |
| cancel_label | no | "Cancel" | Character. Label for the title bar's cancel button (returns NULL). Default "Cancel". Override with wording describing what not drawing anything means in the calling context (e.g. "No More Groups"). |
| viewer | no | shiny::paneViewer(minHeight = 500) | A shiny gadget viewer, passed to runGadget. Default shiny::paneViewer(minHeight = 500) (renders in RStudio's own Viewer pane) -- matches the viewer style already used by this ecosystem's other interactive mapping gadgets (TaxaHabitat::review_spatial_flags()), so all mapping interactions look and feel the same rather than mixing viewer styles. Not dialogViewer (RStudio's own popup dialog) -- on at least one real system, RStudio's embedded dialog webview silently swallowed the Done button's return value for this specific gadget (confirmed reproducible: clicking Done closed the dialog but define_search_polygon() always returned NULL, even though an identical minimal gadget with no leaflet map worked fine in that same dialog viewer, and this exact gadget worked correctly via both shiny::browserViewer() and shiny::paneViewer() in that same session) -- most likely a Leaflet/webview rendering incompatibility specific to that embedded dialog, not something this package can control. Pass shiny::browserViewer() yourself if you'd rather open in your system's default web browser (also confirmed working); avoid dialogViewer() for this function unless you've independently confirmed it round-trips a real click on your machine. |

**Value:** A length-1 character WKT 'POLYGON' string with vertices ordered counter-clockwise and the ring closed (first == last vertex), ready for the 'geometry' argument of 'download_gbif_occurrences'. Returns 'NULL' if the user closes the gadget without clicking Done.

### detect_ranks(input_df, rank_system = NULL, warn = TRUE)

Detect Rank Columns Present in a Data Frame

Intersects column names in 'df' with a reference rank list to find which taxonomy rank columns are present. When 'rank_system' is 'NULL', auto-detects from 'standard_ranks'. Issues a warning when auto-detection finds nothing and falls back to 'c("family", "genus", "species")'.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A data frame whose column names may include taxonomy ranks. |
| rank_system | no | NULL | Character vector of rank names (coarse to fine), or NULL to auto-detect from standard_ranks. |
| warn | no | TRUE | Logical (default TRUE). If TRUE, emits a warning when auto-detection finds no standard rank columns and falls back to the minimum set. |

**Value:** A character vector of rank names present in 'df', ordered coarse to fine. If no ranks are detected even after fallback, returns 'character(0)'.

### draft_methods_text(code, description = NULL, context = NULL, audience = "journal", llm_fn = getOption("TaxaID.llm_fn", call_api), max_code_lines = 300L, verbose = FALSE)

Draft Methods Text from R Code

Reads R code (a script, file path, or character vector of code lines) and uses an LLM to draft a methods section describing the analysis in scientific prose.

| Param | Required | Default | Doc |
|---|---|---|---|
| code | yes |  | Character. One of: A file path to an R script (must exist) A character vector of code lines (e.g., from readLines()) A single string of R code |
| description | no | NULL | Character. Brief study context to guide the LLM (e.g., "eDNA metabarcoding of coral reef fish at Palmyra Atoll using MiFish 12S primers"). Default NULL. Ignored when context is provided (uses context$study_description). |
| context | no | NULL | A report_context object from build_report_context. Provides structured facts (study description, parameters, statistics, citations) that the LLM must use as ground truth. When provided, overrides description. Default NULL. |
| audience | no | "journal" | Character. Target audience: "journal" (default) for peer-reviewed publication style, "technical" for a methods appendix with parameter details, or "brief" for a short summary. |
| llm_fn | no | getOption("TaxaID.llm_fn", call_api) | Function. LLM provider function with signature function(prompt_str, ...) -> character(1). Default getOption("TaxaID.llm_fn", call_api) -- the ecosystem-wide auto-detected provider (see call_api), falling back to call_api itself if the option is unset. |
| max_code_lines | no | 300L | Integer. Maximum number of code lines to include in the prompt. Long scripts are truncated with a note. Default 300L. |
| verbose | no | FALSE | Logical. Print progress messages. Default FALSE. |

**Value:** A character string containing the drafted methods text. Printed to the console via 'cat()' and returned invisibly.

### draft_results_text(..., description = NULL, context = NULL, audience = "journal", code = NULL, llm_fn = getOption("TaxaID.llm_fn", call_api), max_rows = 20L, verbose = FALSE)

Draft Results Text from R Objects

Summarizes R objects (data frames, model outputs, summaries) using an LLM to produce a results section in scientific prose.

| Param | Required | Default | Doc |
|---|---|---|---|
| ... | yes |  | Named R objects to summarize. Names become labels in the prompt (e.g., blast_hits = blast_hits, consensus = consensus_final). Each object is serialized to a text summary suitable for the LLM. |
| description | no | NULL | Character. Brief study context. Default NULL. Ignored when context is provided. |
| context | no | NULL | A report_context object from build_report_context. Provides structured facts the LLM must use as ground truth. Default NULL. |
| audience | no | "journal" | Character. Target audience: "journal" (default), "technical", or "brief". |
| code | no | NULL | Character. Optional R code (file path or lines) that produced the objects. When provided, the LLM can reference specific analysis steps. Default NULL. |
| llm_fn | no | getOption("TaxaID.llm_fn", call_api) | Function. LLM provider function. Default getOption("TaxaID.llm_fn", call_api) -- the ecosystem-wide auto-detected provider (see call_api), falling back to call_api itself if the option is unset. |
| max_rows | no | 20L | Integer. Maximum rows to show per data frame in the prompt. Default 20L. |
| verbose | no | FALSE | Logical. Print progress messages. Default FALSE. |

**Value:** A character string containing the drafted results text. Printed to the console via 'cat()' and returned invisibly.

### escalate_taxonomic_rank(taxon_name, current_rank, rank_system = standard_ranks, max_levels = 2L, backbone_id = 4L, fallback_backbone_id = 11L, verbose = TRUE)

Escalate a Taxon to the Next Coarser Rank

Given a taxon name currently being queried at 'current_rank', looks up its full classification via 'verify_taxon_names()' and returns the name at the next coarser rank in 'rank_system' - e.g. broadening a genus with no reference sequences or occurrence records to its family. If the immediate next-coarser rank is itself absent from the classification path (a gap in the backbone's own data, not a fetch-availability decision), continues walking coarser ranks, up to 'max_levels' steps from 'current_rank', before giving up.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_name | yes |  | Character scalar. The taxon name currently being queried. |
| current_rank | yes |  | Character scalar. The rank taxon_name is at; must be present in rank_system. |
| rank_system | no | standard_ranks | Character vector of rank names, coarse to fine (see standard_ranks). Default standard_ranks. |
| max_levels | no | 2L | Integer. Maximum number of rank levels to walk up from current_rank in a single call. Default 2L (e.g. genus -> family -> order). |
| backbone_id | no | 4L | Integer. Primary backbone for the classification lookup. Default 4L (NCBI). Set NULL to skip straight to fallback_backbone_id. |
| fallback_backbone_id | no | 11L | Integer. Secondary backbone tried if the primary backbone doesn't resolve taxon_name. Default 11L (GBIF). Set NULL or equal to backbone_id to skip. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A list with 'taxon_name' and 'rank'. Both are 'NA_character_' if 'current_rank' is already the coarsest rank in 'rank_system', if the classification cannot be resolved at all, or if no coarser rank resolves within 'max_levels' steps.

### fetch_worms_attributes(taxon_names, cache_dir = NULL, extras = "ncbi_id", accept_fuzzy = FALSE, batch_size = 50L, delay = 0.5, verbose = TRUE)

Fetch WoRMS Taxon Attributes by Name

Looks up taxa in the World Register of Marine Species (WoRMS) *by name* and returns the curated attributes each one carries: the multi-label marine / brackish / freshwater / terrestrial habitat flags, the AphiaID, accepted name and taxonomic status, the WoRMS classification, and optionally the curated NCBI taxon id and a derived introduced-species flag.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of scientific names, at any rank. Genera and higher ranks resolve (Sebastes -> AphiaID 126175; Teleostei -> 293496, a working class node where GBIF's backbone has no occurrence-bearing node for ray-finned fishes at all). Duplicates and NAs are dropped; one row is returned per unique name. |
| cache_dir | no | NULL | Character or NULL (default, no cache). Directory for one small .rds per looked-up name, created if needed. Attributes are curated and do not drift, so there is no TTL; clear it deliberately with taxatools_clear_cache. A cached row records which extras were actually answered, so widening extras later re-fetches only the missing ones and never re-asks for the flags. |
| extras | no | "ncbi_id" | Character vector, any of "ncbi_id" and "wrims"; character(0) for neither. Default "ncbi_id". The habitat flags come free with the batched name match (~50 names per request), but each extra costs one HTTP call per matched taxon, so the fast path for a pure marine-scope filter is extras = character(0). "wrims" is the expensive one (~70 KB per taxon) and is off by default. The schema never changes: a column not requested is NA, except that a cached row already holding it returns it (free -- it is read back, never re-fetched). So an NA here means "not asked for or not held by WoRMS", which is why extras is recorded in the "worms_query" attribute. |
| accept_fuzzy | no | FALSE | Logical, default FALSE. When FALSE only match_type == "exact" records are used. Leave it FALSE for anything that drives a filter. |
| batch_size | no | 50L | Integer, default 50. Names per name-match request. Requests are additionally split to keep the URL under ~6,000 characters, so a batch of long names is chunked further on its own. |
| delay | no | 0.5 | Numeric seconds between requests, default 0.5. Applies between name batches and between per-taxon extra calls. |
| verbose | no | TRUE | Logical, default TRUE. Progress and a summary. |

**Value:** A tibble, one row per unique non-'NA' input name: 'taxon_name' The name as supplied (whitespace trimmed). 'in_worms' Logical. A trusted match was found. 'aphia_id', 'accepted_name', 'accepted_aphia_id', 'taxonomic_status', 'worms_rank' From the representative record (the first 'accepted' match, else the first match). 'match_type' '"exact"', or the rejected match type(s) when 'fuzzy_rejected' ...

### fill_higher_ranks(taxon_names, local_sources = list(), backbone_id = 4L, fallback_backbone_id = 11L, verbose = TRUE)

Fill Higher Taxonomic Ranks from Local Data and Backbone APIs

Given a character vector of taxon names (typically species binomials), derives 'genus' (first word of the binomial) and looks up 'family' using a priority-ordered fallback chain:

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of taxon names. Binomial species names are expected; genus is extracted as the first word. Single-word names (genus only) are accepted and returned as-is in the genus column. |
| local_sources | no | list() | List of data frames to consult before any API call. Each element must contain at least genus and family columns; elements lacking those columns are silently skipped. Sources are consulted in order; the first non-NA family for each genus wins. |
| backbone_id | no | 4L | Integer. Primary backbone for API fallback. Default 4L (NCBI). Set NULL to skip the API entirely. |
| fallback_backbone_id | no | 11L | Integer. Secondary backbone used when backbone_id returns no match. Default 11L (GBIF). Set NULL or equal to backbone_id to skip. |
| verbose | no | TRUE | Logical. Print progress messages for API lookups. Default TRUE. |

**Value:** A tibble with one row per element of 'taxon_names' (preserving duplicates and order), with columns: 'taxon_name' The original input name. 'genus' First word of 'taxon_name', EXCEPT when an API lookup resolved that genus to a backbone-flagged synonym at genus rank - in that case the backbone's own currently-accepted genus name is returned instead (2026-07-25; see @section Genus correction ...

### find_taxonomy_conflicts(input_df, rank_system = NULL)

Find Taxonomic Conflicts in a Taxonomy Data Frame

Detects higher-rank inconsistencies: cases where the same taxon name at one rank is assigned to different parent taxa at a coarser rank across rows.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame with taxonomy columns (e.g. family, genus, species). |
| rank_system | no | NULL | Character vector of rank column names, coarse to fine. If NULL (default), auto-detected via detect_ranks(). |

**Value:** A data frame of conflicts with columns: 'taxon_name' The taxon name that has conflicting higher-rank assignments. 'taxon_rank' The rank of the conflicting taxon (e.g. '"genus"'). 'parent_rank' The coarser rank where disagreement was found (e.g. '"family"'). 'parent_values' Semicolon-separated string of the distinct parent values found (e.g. '"Cottidae; Scorpaenidae"'). 'n_values' Number of ...

### is_plausible_binomial(x)

Test Whether Strings Are Plausible Species Binomials

Returns TRUE for strings that are structurally plausible species binomials matching the '"Genus epithet"' pattern and not matching common placeholder patterns ('sp.', 'cf.', 'aff.', 'uncultured', 'environmental', 'metagenom').

| Param | Required | Default | Doc |
|---|---|---|---|
| x | yes |  | Character vector of taxon name strings. |

**Value:** Logical vector, same length as 'x'.

### list_cache_files(cache_dir, patterns, recursive = FALSE)

List files in a directory matching cache-file patterns

Generic building block for a package's own '<pkg>_clear_cache()' helper: scans 'cache_dir' and returns every file whose basename matches any of 'patterns', with size and modification time. See 'TaxaFetch::taxafetch_clear_cache()'/ 'TaxaLikely::taxalikely_clear_cache()' for worked examples of a downstream package building on this.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | yes |  | Character. Directory to scan. |
| patterns | yes |  | Character vector of regular expressions matched against each file's basename (via grepl()); a file matching ANY pattern is included. |
| recursive | no | FALSE | Logical. Descend into subdirectories? Default FALSE, which is what every caller predating 2026-09-14 assumed. Pass TRUE for a store that keeps part of itself in a subdirectory -- TaxaLikely's per-accession fasta/ cache is one, and while this argument did not exist it was silently unreachable by taxalikely_clear_cache(): 4,061 files no clear function could see. Patterns are still matched against the BASENAME, so a recursive scan needs a pattern that identifies the file, not its directory. |

**Value:** A data frame with columns 'path', 'size_mb', 'mtime' (zero rows if 'cache_dir' has no matching files or does not exist).

### list_models(provider = NULL)

List Current LLM Model Tier Assignments

Shows the model name that each tier ('fast', 'mid', 'top') resolves to for each provider whose API key is set. Also shows the source of the assignment: a session pin, a live API discovery, or the bundled fallback.

| Param | Required | Default | Doc |
|---|---|---|---|
| provider | no | NULL | Character vector. Provider name(s) to show. Default NULL shows all providers with an API key set in the environment. |

**Value:** A data frame (invisibly) with columns 'provider', 'tier', 'model', 'source'.

### model_cache_info()

Show Model Cache Information

Reports the location and age of the local persistent model cache, and the source used by the current session ('"local_cache"' or '"bundled"').

(no parameters)

**Value:** A named list (invisibly) with elements 'path', 'exists', 'age_days', and 'source'.

### new_report_section(package, section, methods, results = NULL, citations = NULL, params = NULL, statistics = NULL)

Create a Report Section Object

Constructor for the 'report_section' S3 class used by per-package report functions throughout the TaxaID ecosystem. Each package's 'report_*()' function returns a 'report_section' object that can be printed standalone or assembled into a unified report via 'assemble_report'.

| Param | Required | Default | Doc |
|---|---|---|---|
| package | yes |  | Character. Package name (e.g. "TaxaFetch"). |
| section | yes |  | Character. Short section identifier (e.g. "fetch", "match", "likelihood"). |
| methods | yes |  | Character. Methods text (template-based, deterministic). |
| results | no | NULL | Character. Results text (template or LLM-generated). |
| citations | no | NULL | Character vector or NULL. Bibliographic citations associated with this pipeline step. |
| params | no | NULL | Named list or NULL. Key parameters used in this step (for reproducibility and downstream assembly). |
| statistics | no | NULL | Named list or NULL. Summary statistics computed in this step. |

**Value:** A 'report_section' object (S3 list).

### parse_classification_path(path, ranks, target_rank)

Parse a Rank Value from a Pipe-Delimited Classification Path

Extracts a single rank value from the 'classification_path' and 'classification_ranks' columns returned by 'verify_taxon_names()'. Both columns use '|' as a delimiter and are positionally aligned.

| Param | Required | Default | Doc |
|---|---|---|---|
| path | yes |  | Character scalar. Pipe-delimited taxon names, e.g. "Animalia\|Chordata\|Cottidae\|Cottus". |
| ranks | yes |  | Character scalar. Pipe-delimited rank labels aligned with path, e.g. "kingdom\|phylum\|family\|genus". |
| target_rank | yes |  | Character scalar. The rank to extract, e.g. "family" or "order". |

**Value:** The matched taxon name string, or 'NA_character_' if 'target_rank' is not present in 'ranks' or inputs are 'NA'.

### prompt_api(prompt, llm_fn = getOption("TaxaID.llm_fn", call_api), pause_seconds = 1, verbose = TRUE)

Submit a Multi-Chunk LLM Prompt to Any Provider

Submits an 'llm_prompt' object to an LLM provider, handling multi-chunk prompts automatically. Provider is selected via the 'llm_fn' argument, which defaults to 'call_api' but accepts any function with the signature 'function(prompt_str, ...) -> character(1)'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt | yes |  | An llm_prompt object (e.g. from build_habitat_prompt() (TaxaHabitat)). |
| llm_fn | no | getOption("TaxaID.llm_fn", call_api) | Function. A provider function that accepts a single character string (the prompt) and returns a single character string (the response). Default: call_api (uses options("TaxaID.provider")). Built-in alternatives: call_anthropic_api, call_gemini_api, call_openai_api, call_ollama_api. To use a non-default model or API key, pass a closure: my_gemini <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash-lite") raw_text <- prompt_api(prompt, llm_fn = my_gemini) |
| pause_seconds | no | 1 | Numeric. Seconds to pause between chunks to avoid rate limits. Default 1. |
| verbose | no | TRUE | Logical. Print progress per chunk. Default TRUE. |

**Value:** A length-1 character string containing the combined raw response text from all chunks.

### prompt_manual(prompt, out_dir = getwd(), prefix = "habitat")

Submit a Prompt Manually via Any LLM Interface

Writes prompt file(s) from an 'llm_prompt' object to disk and prints step-by-step instructions for manual submission to any LLM web interface or desktop app (Path 3). Pauses R execution until the user presses Enter, preventing the next script lines from running prematurely.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt | yes |  | An llm_prompt object (e.g. from build_habitat_prompt() (TaxaHabitat)). |
| out_dir | no | getwd() | Character. Directory to write prompt and response files. Default getwd(). Created if it does not exist. |
| prefix | no | "habitat" | Character. Filename prefix. Default "habitat". Files are named <prefix>_prompt_1.txt, <prefix>_prompt_2.txt, etc. |

**Value:** Invisibly returns a named list: prompt_files Character vector of written prompt file paths. response_files Character vector of expected response file paths. n_chunks Integer. Number of chunks. taxon_list Character vector. All taxa submitted.

### read_llm_response(files)

Read Saved LLM Response File(s)

Reads one or more plain-text LLM response files, strips duplicate CSV headers from chunks 2 onward, and returns a single concatenated string ready for a response parser.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Path(s) to response file(s). Files are read and concatenated in order. For multi-chunk submissions, supply all chunk files in the same order they were submitted. |

**Value:** A length-1 character string.

### refresh_models(providers = NULL)

Refresh LLM Model Discovery from Provider APIs

Queries each provider's '/models' endpoint to find the latest available models, applies tier patterns to assign 'fast'/'mid'/'top' tiers, and saves the results to the local persistent cache. Only providers with an API key set in the environment are queried.

| Param | Required | Default | Doc |
|---|---|---|---|
| providers | no | NULL | Character vector. Provider names to refresh. Default NULL refreshes all providers with keys set. |

**Value:** A data frame of updated tier assignments (invisibly), as from 'list_models'.

### register_provider(name, api_key_var, base_url, fallback_models = list(), tier_patterns = NULL)

Register a Custom OpenAI-Compatible LLM Provider

Adds a custom provider to the session registry so that 'list_models', 'refresh_models', and 'set_model' work with it alongside the built-in providers. Registered providers are also picked up automatically by 'call_openai_api' when its 'base_url' matches.

| Param | Required | Default | Doc |
|---|---|---|---|
| name | yes |  | Character. Short identifier for the provider, e.g. "xai", "groq", "mistral". |
| api_key_var | yes |  | Character. Name of the environment variable holding the API key, e.g. "XAI_API_KEY". Set the key in ~/.Renviron: XAI_API_KEY=xai-.... |
| base_url | yes |  | Character. Base URL of the OpenAI-compatible API, e.g. "https://api.x.ai". The /v1/models and /v1/chat/completions paths are appended automatically. |
| fallback_models | no | list() | Named list with elements fast, mid, and top. Model names to use when live discovery is unavailable. Example: list(fast = "grok-3-mini", mid = "grok-3", top = "grok-3"). |
| tier_patterns | no | NULL | Named list. Regex include/exclude patterns for tier assignment from a live /v1/models response. Same structure as inst/model_tiers.json: list( fast = list(include = "mini", exclude = NULL), mid = list(include = "grok-3$", exclude = "mini"), top = list(include = "heavy", exclude = NULL) ) NULL (default): all tiers map to the first discovered model (no tier differentiation). |

**Value:** The 'name' string invisibly.

### rename_cols(input_df, col_map = NULL, strict = FALSE)

Rename Data Frame Columns to a Target Convention

Renames columns in a data frame using either a user-supplied explicit map or a set of built-in case-insensitive regex patterns that cover common alternatives to DarwinCore column names. Intended as the first step when aligning supplemental occurrence data to a shared column naming convention before combining sources with 'stack_occurrences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A data frame whose columns are to be renamed. |
| col_map | no | NULL | Named character vector or NULL. When supplied, each name is an existing column name in input_df and each value is the desired new name. Both must be quoted strings: col_map = c("Latitude" = "decimalLatitude", "Longitude" = "decimalLongitude", "SurveyDate" = "eventDate") When col_map is supplied it replaces the default pattern matching entirely — only the mappings you specify are applied. When NULL (default), the built-in regex patterns are used instead (see Details). |
| strict | no | FALSE | Logical. Controls behaviour when a col_map key is not found in input_df. FALSE (default): warns about unmatched keys and renames whatever it can. Suitable when rename_cols() is applied to frames that may only contain some of the target columns. TRUE: stops with an error if any col_map key is absent from input_df. Use in scripts where all mappings must succeed. Has no effect when col_map = NULL (default patterns always skip non-matching columns silently). |

**Value:** The input data frame with columns renamed as specified. Column types, row names, and all other attributes are preserved. Columns not mentioned in 'col_map' (or not matched by the default patterns) are left unchanged.

### report_and_clear_cache(inv, label, cache_dir, older_than_days = NULL, dry_run = FALSE)

Report and optionally delete a set of cache files

Shared "apply an age filter, print a summary, delete or dry-run report" engine behind every '<pkg>_clear_cache()'-style helper in this ecosystem. A caller builds its own inventory first - typically via 'list_cache_files()', with any package-specific pre-filtering (e.g. TaxaFetch's own orphan detection) already applied - and hands it to this function to do the rest.

| Param | Required | Default | Doc |
|---|---|---|---|
| inv | yes |  | A data frame with path, size_mb, mtime columns, as returned by list_cache_files(). |
| label | yes |  | Character. Name shown in messages -- typically the calling <pkg>_clear_cache() function's own name, so a user sees which function actually printed a given message. |
| cache_dir | yes |  | Character. Shown in messages only; inv is used as-is and is not re-scanned. |
| older_than_days | no | NULL | Numeric or NULL. When supplied, only rows of inv older than this many days (by mtime) are targeted. NULL (default) targets every row of inv. |
| dry_run | no | FALSE | Logical. If TRUE, reports what would be removed without removing anything. Default FALSE. |

**Value:** Invisibly, the (possibly 'older_than_days'-filtered) subset of 'inv' that was targeted.

### reset_token_usage()

Reset the LLM Token Usage Ledger

Clears all accumulated token records for the current session. Call this before starting a new workflow step when you want per-step accounting.

(no parameters)

**Value:** 'NULL' invisibly.

### resolve_barcode_lengths(barcode_term, min_len = NULL, max_len = NULL)

Resolve Barcode Length Bounds from a Barcode Term

Looks up 'barcode_term' in barcode_length_defaults and returns 'c(min_bp, max_bp)'.

| Param | Required | Default | Doc |
|---|---|---|---|
| barcode_term | yes |  | Character vector of barcode marker names (e.g. "MiFishU", "COI", c("12S", "16S")). |
| min_len | no | NULL | Optional integer overrides. When non-NULL, replace the auto-detected bound. |
| max_len | no | NULL | Optional integer overrides. When non-NULL, replace the auto-detected bound. |

**Value:** Integer vector of length 2: 'c(min_bp, max_bp)'.

### resolve_barcode_marker(barcode_term)

Resolve a Primer-Variant Barcode Term to the Marker It Amplifies

A registered primer-variant name (see barcode_primer_defaults) - '"COI-Folmer"', '"16S-Palumbi"', '"rbcLa"' - is the correct term for resolving primers and amplicon lengths, but it is *not* a term any sequence database indexes: no GenBank record is tagged "Folmer". A search query built from the variant name matches nothing, and because "nothing found" is a legitimate outcome of a search, that failure is silent - it looks like the taxon has no barcode rather than like a bad query.

| Param | Required | Default | Doc |
|---|---|---|---|
| barcode_term | yes |  | Character vector of barcode/marker/primer-variant names. |

**Value:** Character vector the same length as 'barcode_term': the base marker name for a recognised primer variant, otherwise the input unchanged.

### resolve_barcode_primers(barcode_term)

Resolve Primer Sequences from a Barcode/Primer-Set Term

Looks up 'barcode_term' in barcode_primer_defaults. Unlike 'resolve_barcode_lengths()', matching requires the _specific_ primer variant (e.g. '"MiFishU"', not bare '"MiFish"') because different variants of what is loosely called "the same marker" can have genuinely different primer sequences - silently picking one would be a real correctness risk, not a convenience shortcut. An ambiguous or unlisted term errors with guidance rather than guessing.

| Param | Required | Default | Doc |
|---|---|---|---|
| barcode_term | yes |  | Character scalar naming a specific primer set (e.g. "MiFishU", "mifish-e"). Matching is case-insensitive and ignores -/_/space separators. |

**Value:** A list with 'fwd', 'rev' (character, 5'-3') and 'amplicon_range' (integer 'c(min_bp, max_bp)').

### scientific_to_common(scientific_names, backbone_id = 11L, location = NULL, use_llm = FALSE, llm_fn = getOption("TaxaID.llm_fn"), cache_dir = NULL, verbose = TRUE, ...)

Convert Scientific Names to Common Names

Looks up English common names for a character vector of scientific names. By default queries the GBIF vernacular names database ('backbone_id = 11') or ITIS ('backbone_id = 3'); a backbone miss is left as 'NA' unless 'use_llm = TRUE' is explicitly requested (the default is 'FALSE', not 'TRUE'). Set 'backbone_id = NULL' to use the LLM for all names without a backbone query.

| Param | Required | Default | Doc |
|---|---|---|---|
| scientific_names | yes |  | Character vector of scientific names to look up. |
| backbone_id | no | 11L | Integer or NULL. Backbone for structured lookup: 11 = GBIF (default, uses rgbif), 3 = ITIS (uses taxize). Other values trigger a warning and fall through to the LLM. NULL skips backbone lookup entirely. |
| location | no | NULL | Character string providing geographic context for the LLM (e.g., "Southern California Bight", "Pacific Northwest, USA"). Biases the LLM toward regionally appropriate common names. Has no effect on backbone-sourced results. Default NULL. |
| use_llm | no | FALSE | Logical. If TRUE, taxa with no backbone result are sent to the LLM in batches of 20 names (one progress line per batch when verbose). Default FALSE: returns NA for unresolved taxa without an LLM call. A name the LLM omits from its batch response is NOT cached (per-row llm_parsed, 2026-09-13) -- it is re-asked on a later call rather than silently treated as a confirmed "no common name" answer. |
| llm_fn | no | getOption("TaxaID.llm_fn") | Function with signature function(prompt, ...) -> character(1). Required when use_llm = TRUE or backbone_id is unsupported / NULL. Default getOption("TaxaID.llm_fn"). |
| cache_dir | no | NULL | Character or NULL (default, no cache). A directory holding one small .rds per looked-up name, keyed on the name (case/whitespace-insensitive), backbone_id and location. A name found there is served without any backbone or LLM call; a name resolved this call is written back. A name the LLM was asked about and answered "no common name" IS cached (that is its answer); a name from a batch the LLM answered unparseably is NOT (it will be re-asked), and neither is a backbone miss on a use_llm = FALSE call (a later use_llm = TRUE call must still be able to ask). Manage it with taxatools_clear_cache. Added 2026-09-12: a real 18S workflow spent 58 silent LLM calls on 1,151 names, then repeated them on every re-run. |
| verbose | no | TRUE | Logical (default TRUE). Print a one-line summary (cache / backbone / LLM counts) and one line per LLM batch. |
| ... | yes |  | Additional arguments passed to llm_fn. |

**Value:** A data frame with one row per element of 'scientific_names': 'scientific_name' Input scientific name (character). 'common_name' Primary English common name, or 'NA'. 'common_name_alternatives' Semicolon-delimited additional English common names, or 'NA'. 'source' One of '"gbif"', '"itis"', '"llm"', or '"none"'. 'backbone_id' Integer backbone ID used, or 'NA' for LLM or no-result rows.

### set_model(provider, tier, model)

Pin a Specific Model Version for Reproducibility

Overrides dynamic tier resolution for the current R session. Use at the top of an analysis script to lock the exact model version, ensuring results can be reproduced regardless of what the provider currently returns as 'latest'.

| Param | Required | Default | Doc |
|---|---|---|---|
| provider | yes |  | Character. Provider name: "anthropic", "gemini", "openai", or "azure_openai". |
| tier | yes |  | Character. Tier to pin: "fast", "mid", or "top". |
| model | yes |  | Character. Exact model identifier to use, or NULL to remove an existing pin. |

**Value:** The model string invisibly.

### taxaid_build_manifest(packages = NULL)

Record Which TaxaID Code a Run Is Using

Captures, for each TaxaID package, its version, 'Built' timestamp and a hash of its installed code. Save it beside a run's outputs and every result becomes traceable to the exact build that produced it.

| Param | Required | Default | Doc |
|---|---|---|---|
| packages | no | NULL | Character vector of package names. Defaults to the nine TaxaID packages. |

**Value:** A data frame with columns 'package', 'version', 'built', 'code_hash', 'installed'. Packages that are NOT installed appear with 'installed = FALSE' rather than being dropped - absence has to be representable for 'check_taxaid_manifest()' to report it.

### taxaid_cache_report(extra_dirs = NULL, warn_gb = 1)

Report every TaxaID cache on this machine

The ecosystem had five package-specific '<pkg>_clear_cache()' functions and no way to see the whole picture, which is how it accumulated a 23 GB and then a 17 GB cache without anyone noticing (38 GBIF zips at 17.0 GB against 52 MB for every other cache file combined). This is the missing ecosystem-level view: it reports, and never deletes.

| Param | Required | Default | Doc |
|---|---|---|---|
| extra_dirs | no | NULL | Character vector of additional cache directories to include -- typically the project-local ones a workflow passes as cache_dir. Non-existent paths are reported as missing rather than dropped, so a typo is visible. |
| warn_gb | no | 1 | Numeric. Directories at or above this size are flagged in the printed output. Default 1. Set NULL to disable flagging. |

**Value:** Invisibly, a data frame with one row per directory: 'cache', 'path', 'exists', 'n_files', 'size_mb', 'oldest', 'newest'. 'size_mb' is APPARENT size (sum of file bytes). A cache of many tiny files occupies substantially more than that on disk, because each file takes at least one filesystem block - TaxaLikely's per-taxon and per-accession stores are thousands of ~1 KB files, so their real ...

### taxatools_clear_cache(cache_dir, older_than_days = NULL, dry_run = FALSE)

Report and clear the TaxaTools on-disk caches

Covers both of the package's file-per-key caches: 'scientific_to_common(cache_dir = )' (one '.rds' per looked-up name) and 'fetch_worms_attributes(cache_dir = )' (one '.rds' per looked-up taxon). This helper reports what the directory holds and deletes it (optionally only files older than 'older_than_days'), via the shared 'report_and_clear_cache' engine - the same shape as 'TaxaFetch::taxafetch_clear_cache()' and 'TaxaFlag::taxaflag_clear_cache()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | yes |  | Character. The directory passed to scientific_to_common(cache_dir = ) or fetch_worms_attributes(cache_dir = ). |
| older_than_days | no | NULL | Numeric or NULL. Only files older than this many days are targeted; NULL (default) targets every file. |
| dry_run | no | FALSE | Logical. If TRUE, reports without deleting. |

**Value:** Invisibly, the data frame of targeted files (see 'list_cache_files').

### to_faire(input_df, table_type = c("taxaFinal", "taxaRaw"), checkls_ver = "1.02", assay_name = NULL)

Export a TaxaID Data Frame in FAIRe Checklist Format

Converts a TaxaID output data frame (match object, likelihood object, or posterior object) to the column naming conventions of the FAIRe eDNA metadata checklist (Takahashi et al. 2025), specifically the 'taxaRaw' and 'taxaFinal' classes.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A TaxaID data frame. Any output from TaxaMatch, TaxaLikely, or TaxaAssign is accepted. Columns not covered by the FAIRe field mapping are retained with their original names. |
| table_type | no | c("taxaFinal", "taxaRaw") | Character. "taxaFinal" (post-curation assignments, e.g. posterior consensus output; default) or "taxaRaw" (pre-curation assignments, e.g. direct match output). Affects only the faire_table attribute attached to the returned data frame. |
| checkls_ver | no | "1.02" | Character. FAIRe checklist version to record in the checkls_ver column. Default "1.02" (current stable version). |
| assay_name | no | NULL | Character or NULL. Value to use for the FAIRe assay_name field when df does not contain a testid column. If NULL and testid is absent, assay_name is omitted from the output with a message. |

**Value:** A data frame with FAIRe-compatible column names and a 'faire_table' attribute recording 'table_type' and 'checkls_ver'.

### token_usage(by = c("call", "function", "provider", "session"), cost_per_1k_input = NULL, cost_per_1k_output = NULL)

Summarise LLM Token Usage for the Current Session

Returns a data frame of token usage records accumulated since the last call to 'reset_token_usage' (or since 'library(TaxaTools)'). Every call to 'call_api' appends one record automatically; no changes are needed in downstream package functions.

| Param | Required | Default | Doc |
|---|---|---|---|
| by | no | c("call", "function", "provider", "session") | Character. How to aggregate: "call": One row per individual API call (default). Includes timestamp, caller function, provider, model, and token counts. "function": Totals per caller function. "provider": Totals per provider. "session": Single-row grand total for the session. |
| cost_per_1k_input | no | NULL | Numeric or NULL. If supplied, adds a cost_usd column estimated as (input * cost_per_1k_input + output * cost_per_1k_output) / 1000. Default NULL (no cost column). |
| cost_per_1k_output | no | NULL | Numeric or NULL. Output cost rate. Used only when cost_per_1k_input is non-NULL. Default NULL (same rate as input). |

**Value:** A data frame. Columns depend on 'by': '"call"' 'timestamp', 'caller', 'provider', 'model', 'input', 'output', 'total' '"function"' 'caller', 'n_calls', 'input', 'output', 'total' '"provider"' 'provider', 'n_calls', 'input', 'output', 'total' '"session"' 'n_calls', 'input', 'output', 'total' Returns an empty data frame with a message if no calls have been recorded.

### verify_taxon_names(name_list, backbone_id, batch_size = 500, timeout_sec = 30, fallback_backbone_id = 11L)

Verify Taxon Names Against a Taxonomic Backbone

Checks a vector of taxon names against a target taxonomic backbone using the Global Names Verifier API (v1). Returns the best match for each name along with classification path, ranks, a match score, and a flag indicating whether verification succeeded.

| Param | Required | Default | Doc |
|---|---|---|---|
| name_list | yes |  | A character vector of taxon names to verify. Duplicates are removed automatically. |
| backbone_id | yes |  | Integer. The numeric ID of the target taxonomic backbone. Common options: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS, 11 = GBIF. See https://verifier.globalnames.org/ for the full list. |
| batch_size | no | 500 | Integer. Maximum number of names per API request. The Global Names Verifier API supports up to 1000 names per batch. Default is 500 to stay safely within limits. |
| timeout_sec | no | 30 | Integer. Seconds to wait before the API request times out. Default is 30. |
| fallback_backbone_id | no | 11L | Integer. Only used when backbone_id = 4 (NCBI). NCBI's direct lookup is an exact string search with no typo tolerance -- a single misspelled letter returns zero hits even via its own synonym fallback. When that happens, this backbone's Global Names Verifier API is queried instead purely to suggest a corrected spelling, which is then re-resolved through NCBI itself (the correction is never accepted from this backbone directly, so NCBI's own classification -- the reason the direct bypass exists at all -- is preserved). Default 11 (GBIF). Must not be 4. |

**Value:** A tibble with one row per input name and the following columns: user_supplied_name The original name as supplied. matched_name The best-matched name at whatever rank the backbone actually resolved it to (authorship strings stripped; a genus-only match returns a bare genus, a subspecies-level match returns the full trinomial), or 'NA' if no match was found. When the backbone itself flags the ...

### write_taxaid_manifest(path, packages = NULL)

Write a TaxaID Build Manifest

Write a TaxaID Build Manifest

| Param | Required | Default | Doc |
|---|---|---|---|
| path | yes |  | File path to write (.rds). |
| packages | no | NULL | Passed to taxaid_build_manifest(). |

**Value:** The manifest, invisibly.

## Quick Start

### Clean and verify a messy name list

``` r
library(TaxaTools)

raw_names <- c("Gadus_morhua", "sebastes sp.", "Paracalanus parvus (Claus, 1863)")

cleaned <- clean_taxon_names(raw_names)
#> "Gadus morhua" "Paracalanus parvus" (the "sp." entry is dropped)

verified <- verify_taxon_names(cleaned, backbone_id = 11)  # GBIF
# verified$matched_name / matched_rank / is_synonym / classification_path
```

### Verify the same name against different taxonomic backbones

`backbone_id` selects which authority resolves a name. Backbones don't
always agree -- a name can be a live species in one and a retired synonym
in another (`is_synonym`/`matched_rank` will differ), which is exactly why
downstream packages let the caller choose rather than hardcoding one:

| `backbone_id` | Backbone |
|----|-----------------------------------|
| 1 | Catalogue of Life |
| 3 | ITIS (Integrated Taxonomic Information System) |
| 4 | NCBI |
| 9 | WoRMS (World Register of Marine Species) |
| 11 | GBIF |

``` r
# Same query, five backbones -- compare matched_name/is_synonym across them
backbones <- c(col = 1, itis = 3, ncbi = 4, worms = 9, gbif = 11)

lapply(backbones, function(id) {
  verify_taxon_names("Urobatis halleri", backbone_id = id)[
    , c("matched_name", "matched_rank", "is_synonym")
  ]
})
```

A mismatch here isn't a bug in `verify_taxon_names()` -- it's telling you
the backbones themselves disagree, which matters when joining data that
was verified against different ones (e.g. sequence references verified
against NCBI, occurrence records verified against GBIF).

### Call an LLM without knowing which provider is configured

``` r
# .onAttach() already set options(TaxaID.llm_fn) from your ~/.Renviron
response <- call_api("Summarize the habitat preferences of Gadus morhua in one sentence.")
```

### Resolve a barcode marker's expected amplicon length and primers

``` r
resolve_barcode_lengths("MiFish")               # list(min = 163L, max = 185L)
resolve_barcode_primers("MiFish-U")             # list(fwd = ..., rev = ..., amplicon_range = ...)
resolve_barcode_marker("COI-Folmer")            # "COI" -- the term a sequence database actually indexes
```

### Convert between common and scientific names

``` r
common_to_scientific(c("Pacific cod", "sablefish"), taxonomic_group = "fish")
scientific_to_common("Gadus macrocephalus", backbone_id = 11)
```

