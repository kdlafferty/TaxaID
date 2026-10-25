# CONTEXT: TaxaTools

**Uploads, standardizes and corrects taxonomy across backbones**

Provides helper functions for cleaning, verifying, and standardizing taxonomic names across multiple backbones. Capabilities include spell-checking and correcting species names, translating names between taxonomic backbones (e.g., GBIF, NCBI, WoRMS), retrieving classification hierarchies via API, and creating standardized taxon labels at any rank. Also provides LLM provider functions for calling Anthropic, OpenAI, Gemini, and Ollama APIs, and LLM-assisted text generation for drafting methods and results sections. Part of the TaxaID ecosystem.

Version 1.0.0. 53 exported function(s).

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

### assign_sampling_group(taxonomy, scheme = default_sampling_scheme(), rank_cols = c("kingdom", "phylum", "class", "order"), kingdom_guard = TRUE, harmonise = FALSE, backbone_id = 11L, cache_dir = NULL, verbose = TRUE, decisions = NULL)

Assign Sampling Groups from Taxonomic Rank Columns

Classifies each row of a taxonomy table into a 'sampling_group' (the shared-effort denominator, kernel-fit group, and dark-diversity-floor group used throughout the TaxaID ecosystem) using an ordered, first-match-wins rule scheme - see 'default_sampling_scheme'. This is the single package-level home for this classification logic, so every caller uses the exact same rule set.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxonomy | yes |  | A data frame (or tibble) with at least some of the columns named in rank_cols. Returned as-is with a new sampling_group column added. |
| scheme | no | default_sampling_scheme() | A sampling-group scheme object; see default_sampling_scheme for the required shape. Supply a custom scheme (e.g. default_sampling_scheme() with an appended or edited rule) to override the default classification -- the whole rules/catch_all/kingdom_guard_vocabulary object is used exactly as supplied, with no merging against the default. |
| rank_cols | no | c("kingdom", "phylum", "class", "order") | Character vector of taxonomic rank columns to read, in COARSE-TO-FINE order. Default c("kingdom", "phylum", "class", "order") -- the four ranks every rule in default_sampling_scheme() reads. A column absent from taxonomy is treated as entirely NA (never an error), so a taxonomy table missing e.g. order still classifies on the ranks it does have. |
| kingdom_guard | no | TRUE | Logical, default TRUE. When a row reaches the catch-all (scheme$catch_all, normally "macroinvertebrates") and its kingdom is NOT one of scheme$kingdom_guard_vocabulary (default c("Animalia", "Metazoa")), the row's sampling_group is set to NA instead of the catch-all. This is the single mechanism that closes the open-ended protist tail: rather than enumerating every non-animal class GBIF's backbone might ever produce (Heliozoa, Amoebozoa, Ascomycota, Chytridiomycota, Foraminifera, ... -- an unbounded and ever-growing list), any row whose kingdom is not plausibly an animal is refused the animal-flavoured catch-all ("macroinvertebrates" literally means "not a vertebrate ANIMAL") and surfaced as NA instead, where it is visible to a caller auditing unmatched rows rather than silently, indefinitely counted as a benthic invertebrate. Where the kingdom cannot settle it -- "Eukaryota" or "Eukarya", which are true of every taxon here and so say nothing, or no usable value at all -- the PHYLUM decides instead, against scheme$animal_phyla, trimmed and case-insensitively. The kingdom comparisons are trimmed and case-insensitive too, so a mis-cased or space-padded kingdom is not mistaken for an unrecognised one. "Bacteria" and "Archaea" are NOT in that set: they settle the question outright, so the allowlist refuses them and the phylum is never consulted. A scheme carrying no animal_phyla borrows default_sampling_scheme()'s list, with a message, rather than treating every phylum as non-animal. A known animal phylum keeps the catch-all; an informative phylum that is not an animal one is refused, which is a conclusion rather than a default because the animal phyla are a closed set; and a phylum that is itself missing or a placeholder is refused with sampling_group_basis = "unknown_phylum", because no decision is possible and saying so is better than guessing either way. A row with no usable taxonomy is therefore visible to a caller auditing unmatched rows, which is what the guard was always for, rather than being counted indefinitely as a benthic invertebrate. A missing kingdom VALUE and a missing kingdom COLUMN are different statements, and are treated differently. A row whose kingdom is NA is decided on its phylum, as above. A taxonomy with no kingdom column at all is still decided on its phylum if it HAS a phylum column; only when BOTH columns are absent -- a class/order-only table, which this function supports -- is there nothing to decide on, and then every unmatched row keeps the catch-all as before, with one warning naming the columns it could not find. Note for a caller with a DOWNSTREAM gate that drops units whose every candidate is out of scope: a candidate whose only in-scope status came from a bare domain label is now out of scope, so such a gate may drop units it previously kept, and its own identity hold should be set. Set kingdom_guard = FALSE to make every unmatched row (any kingdom, including NA) become the catch-all instead; that disables the phylum fallback with it. |
| harmonise | no | FALSE | Logical, default FALSE. When TRUE, taxonomy is harmonised to scheme's backbone BEFORE classification, via verify_taxon_names(backbone_id = backbone_id) -> change_backbone(). This lets an NCBI-backbone match object (e.g. one carrying class = "Copepoda", class = "Thalassiosirophyceae", or kingdom "Chromista"/"Protozoa" in vocabulary the default scheme does not otherwise recognise) be classified correctly against a GBIF-vocabulary scheme, at a real cost: one backbone name-verification lookup per unique value at the finest available rank in rank_cols (so, typically, one call per unique order value -- cheap relative to a per-species lookup, but not free, and it is a live API call unless cache_dir serves it from a prior run). harmonise is OFF by default specifically because of this cost -- most callers already have GBIF-vocabulary taxonomy and gain nothing from paying it. A rank name that fails to resolve keeps its ORIGINAL value rather than becoming NA (matches the source and never silently loses taxonomy), and so does one the backbone resolves at the WRONG RANK -- see the Rank agreement section, which is what stops a homonym at another rank from overwriting the row's whole lineage. |
| backbone_id | no | 11L | Integer backbone ID passed to verify_taxon_names when harmonise = TRUE. Default 11L (GBIF), matching default_sampling_scheme()'s own vocabulary. Ignored when harmonise = FALSE. |
| cache_dir | no | NULL | Optional directory for a persistent, content-keyed cache of the harmonisation lookup (one .rds file, keyed on the sorted unique rank names actually resolved) -- only used, and only relevant, when harmonise = TRUE. NULL (default) does no caching, so every call re-resolves every unique name. |
| verbose | no | TRUE | Logical, default TRUE. Print one table of the resulting sampling_group counts (including the NA count) after classification, and progress messages during harmonisation. |
| decisions | no | NULL | Only relevant when harmonise = TRUE and backbone_id = 4 (NCBI) -- forwarded verbatim to verify_taxon_names's own decisions parameter. This function grows no prompt or resolution logic of its own for an NCBI name collision. |

**Value:** 'taxonomy' (or its harmonised copy, when 'harmonise = TRUE') with TWO new character columns added. 'sampling_group': 'NA' where no rule matched AND the kingdom guard or the phylum fallback refused the row; otherwise always one of the group names in 'scheme$rules' or 'scheme$catch_all'. 'sampling_group_basis': WHY that value, so that a caller counting dropped rows can say which decision dropped them rather than only how many. One of '"rule"' (a scheme rule matched, at any rank), '"catch_all"' (no rule matched and the kingdom was an accepted animal one), '"kingdom_guard"' (refused on an informative non-animal kingdom), '"phylum_animal"' (the kingdom could not decide and the phylum is an animal one, so the catch-all stands), '"phylum_non_animal"' (refused on the phylum) or '"unknown_phylum"' (neither rank could decide; see 'kingdom_guard').

#### Empty-string normalisation

"" is normalised to NA across every present rank_cols column BEFORE classification. Real GBIF-derived taxonomy stores "unclassified at this rank" as an empty string, not NA -- the same real-data quirk TaxaExpect::compute_adaptive_sampling_groups() and TaxaAssign::join_priors() already normalise this way. This is behaviour-neutral for every ==/%in% test in the scheme ("" and NA both fail them identically), but it is what lets the class-less-Chordata fish clause be written honestly as "class is missing" rather than as a fragile class != "" check.

#### Backbone-mismatch detection (harmonise = FALSE)

When harmonise = FALSE, this function makes two cheap, static checks for signs the input taxonomy is NOT in the scheme's expected GBIF vocabulary, and emits ONE warning (naming what it saw) if either fires: (1) a taxonomy_backbone attribute on taxonomy that does not look like GBIF/backbone 11; (2) a class value GBIF's backbone is known NOT to carry: "Thalassiosirophyceae", "Bigyra" or "Phytomastigophora". "Copepoda" is deliberately NOT used as a mismatch signal: although NCBI-flavoured, it also occurs in GBIF-backbone occurrence data, so it is handled directly in the zooplankton rule (see default_sampling_scheme), and treating it as a symptom would warn falsely on correct GBIF input. The check is a heuristic, not exhaustive, and it errs toward naming what it saw. Passing harmonise = TRUE (or verifying the input's backbone directly) is the reliable fix, not a substitute for reading the warning.

#### Rank agreement (harmonise = TRUE)

The harmoniser resolves each row's finest available rank NAME and then overwrites kingdom/phylum/class/order from the lineage the backbone returns. That is safe only if the backbone's answer is about the SAME TAXON the probe column named, so a resolution is accepted only when one of two things holds:

- verify_taxon_names's matched_rank equals the rank of the probe column. This is the ordinary case, and it keeps SYNONYM resolution working: an outdated spelling resolves to the backbone's accepted name, which is not the name that was asked about, so only the rank can vouch for it.

- The rank differs, but the returned lineage carries the probe name ITSELF at the probe's own rank. That is a same-clade duplication rather than a homonym: GBIF holds a genus Spionidae inside family Spionidae and a genus Arthropoda inside phylum Arthropoda, so the terminal match is a genus while every rank above it is the lineage the row already had.

A row failing both keeps its ORIGINAL taxonomy, the same fallback an unresolved name gets, and is named in a warning.

The gate exists because of cross-lineage homonyms, which would otherwise rewrite a whole lineage into an unrelated one. For example, GBIF's backbone contains a tachinid fly genus named Polychaeta (Animalia|Arthropoda|Insecta|Diptera|Tachinidae|Polychaeta). Without the gate, a row whose class reads "Polychaeta" (the annelid class, correct in NCBI) would match that genus and have its lineage overwritten (Annelida -> Arthropoda, Polychaeta -> Insecta, and a fabricated order = "Diptera"), be grouped as terrestrial_arthropods, and, because a downstream marine filter reads the harmonised phylum/class, be silently dropped from the species list. Other NCBI-side names with the same hazard: lll name column rank what GBIF matched Polychaeta class a tachinid fly genus (Insecta|Diptera) Ctenophora phylum a crane-fly genus (Insecta|Diptera) Ciliophora phylum a FUNGUS genus (Fungi|Ascomycota) Appendicularia class a flowering-plant genus (Plantae|Myrtales) Pilidiophora class a gregarine genus (Chromista|Myzozoa)

Some rank disagreements are NOT homonyms: "Bacillariophyta" (NCBI phylum, GBIF class Bacillariophyceae) and "Bigyra" (NCBI class, GBIF phylum) are genuine NCBI-vs-GBIF rank-assignment differences for the same clade. Rejecting them is harmless: the row keeps its NCBI value, and the diatom rule in default_sampling_scheme is class-level by design.

A cache written before this gate existed carries no matched_rank and cannot be checked, so it is discarded and re-resolved rather than trusted.

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

#### Details

This function is domain-agnostic. It works for any analysis workflow -- ecological surveys, clinical trials, economic models, etc. Domain-specific details (e.g., molecular markers, study sites, model types) belong in the facts parameter as named key-value pairs.

The context object is intentionally simple -- a named list with a class attribute and a print method. All fields are optional. The LLM prompt is built only from fields that are non-NULL, so a minimal context with just study_description is valid.

Why use a context? Without a context, the LLM infers facts from code comments and data summaries, which may be incomplete or ambiguous. The context lets you provide verified numbers and details that the LLM must use as ground truth, reducing hallucination and ensuring consistency between the methods and results text.

statistics vs. facts: Use statistics for numeric results (sample sizes, rates, counts) and facts for non-numeric domain knowledge (study location, equipment, species groups). statistics are presented to the LLM under a "Statistics" heading and are restricted to the results text. facts appear under "Additional facts" and may appear in either methods or results.

Reuse: Build one context object and pass it to both draft_methods_text() and draft_results_text() for consistent grounding across sections.

Pipeline-specific packages can provide helper functions that extract facts from their output objects and pass them here (e.g., a TaxaAssign helper that reads report_params attributes from posterior output and consensus objects).

### cache_ok(path, inputs = NULL)

Is a cache file usable, given the inputs it derives from?

A cache gate that tests only 'file.exists()' silently serves stale results. This is the ecosystem's staleness primitive: a cache is usable only if it exists AND is not older than any of the artifacts it was derived from. Every package file that takes a 'cache_dir' argument shares this one implementation.

| Param | Required | Default | Doc |
|---|---|---|---|
| path | yes |  | Character. Path to the candidate cache file. |
| inputs | no | NULL | Character vector or NULL. Paths this cache was derived FROM. Missing and NA entries are ignored, so a caller can pass an optional upstream without branching. If any surviving input is newer than path, the cache is rejected. |

**Value:** 'TRUE' if 'path' exists and no declared input is newer; 'FALSE' otherwise. Rejection emits a message naming the culprit.

#### When inputs applies

Declare inputs whenever a cache derives from a file the caller itself writes -- a checkpoint, a bounding box, an upstream .rds. That is the case this function detects. It does NOT help for a cache whose upstream is a remote service (an NCBI or GBIF query has no local mtime to compare against); that staleness axis is time, and the policy for it is to report the cache's age at load rather than expire it silently.

### call_anthropic_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), max_tokens = 16000L, api_key = Sys.getenv("ANTHROPIC_API_KEY"), temperature = NULL)

Call the Anthropic API with a Single Prompt String

Low-level generic function: submits one plain character string to the Anthropic Messages API and returns the model's response as a plain character string. No chunking, no S3 class requirements, no domain-specific logic. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Exact Anthropic model identifier, e.g. "claude-sonnet-4-6". Default NULL resolves to the latest model for tier via list_models. Specify an exact model to pin a version for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast" (cheapest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. |
| max_tokens | no | 16000L | Integer. Ceiling on the tokens the model may produce (default 16000). A cap, not an allocation, so a generous value costs nothing extra; it is generous because a reasoning model spends part of the budget thinking before it writes, and a cap sized for the visible answer alone returns a response with no text in it. Sufficient for most taxonomy and habitat prompts. Increase for longer outputs (e.g., large species lists). Higher values increase API cost. |
| api_key | no | Sys.getenv("ANTHROPIC_API_KEY") | Character. Anthropic API key. Defaults to the ANTHROPIC_API_KEY environment variable. |
| temperature | no | NULL | Numeric or NULL. Passed to call_api; NULL (default) sends no temperature, keeping the provider default. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status.

#### Details

Use this directly when you have already built your own prompt string (e.g. for geographic screening, PDF extraction, or any ad-hoc task). For habitat assignment with a build_habitat_prompt() (TaxaHabitat) object, use prompt_api instead -- it handles chunking and per-chunk retries automatically.

### call_api(prompt_str, provider = NULL, tier = c("mid", "fast", "top"), model = NULL, max_tokens = 16000L, api_key = NULL, base_url = NULL, images = NULL, show_tokens = FALSE, max_input_tokens = NULL, timeout = 120, temperature = NULL)

Call Any Configured LLM with a Single Prompt String

Generic provider-neutral function. Resolves the provider, model, API key, and endpoint from the registry ('inst/model_tiers.json' plus any session entries added via 'register_provider'), builds the provider-appropriate HTTP request, and returns the model's response as a plain character string.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| provider | no | NULL | Character. Provider name: "anthropic", "gemini", "openai", "azure_openai", "ollama", or any name registered with register_provider. Default NULL uses options("TaxaID.provider"), which is set automatically by library(TaxaTools) based on detected API keys. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier when model = NULL: "fast" (cheapest/smallest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. Tier-to-model mapping is discovered live from the provider's /models endpoint (see list_models). |
| model | no | NULL | Character. Exact model identifier. Overrides tier resolution. Use to pin a specific version for reproducibility. |
| max_tokens | no | 16000L | Integer. Ceiling on the tokens the model may produce for this call (default 16000). It is a cap, not an allocation: a short answer costs a short answer, so raising it does not raise the bill. The default is generous because a reasoning model spends part of the budget thinking before it writes anything, and a cap sized for the visible answer alone returns a response carrying no text at all. Raise it further for a long structured answer over a long prompt. The correct request body field for the provider (max_tokens vs max_completion_tokens) is read from the registry automatically. |
| api_key | no | NULL | Character. API key override. Default NULL reads the key from the environment variable named in the provider's registry entry (e.g. ANTHROPIC_API_KEY). Keyless providers (Ollama) ignore this. |
| base_url | no | NULL | Character. Base URL override for OpenAI-compatible providers (OpenAI, Azure, Ollama, custom registered providers). Default NULL uses the provider's registered endpoint. For Ollama: change the host/port, e.g. base_url = "http://remote-server:11434". For OpenAI-compatible proxies: supply the proxy base URL. For Azure: replaces the host in the endpoint template while preserving the deployment path and API version. |
| images | no | NULL | Named list of base64-encoded PNG strings, as returned by .render_pdf_pages() in the TaxaFetch PDF pipeline. Default NULL (text-only call). When supplied, the prompt and images are sent as a multi-modal message using the provider's vision format: Anthropic image content blocks, Gemini inlineData parts, or OpenAI image_url blocks. Requires a vision-capable model (e.g. Claude Sonnet, Gemini 2.5 Flash, GPT-4o). |
| show_tokens | no | FALSE | Logical. When TRUE, prints a message after each call reporting the provider, model, and token counts (e.g. "Tokens used [anthropic / claude-sonnet-4-6] -- input: 312, output: 87"). Default FALSE to avoid output in non-interactive workflows. Token counts are retrieved from the provider's response body; NA is reported when a provider does not return usage information. |
| max_input_tokens | no | NULL | Integer or NULL. When non-NULL, estimates the prompt length as ceiling(nchar(prompt_str) / 3.5) (a conservative characters-per-token heuristic) and stops with an informative error before making the HTTP request if the estimate exceeds the limit. Use this as a pre-flight guard against accidentally sending very large prompts. Default NULL (no check performed). |
| timeout | no | 120 | Numeric. Request timeout in seconds, passed to httr2::req_timeout(). Default 120. Raise this for a slow provider/model (e.g. a large local Ollama model) or a large multi-image PDF-vision call that can legitimately take longer than two minutes. |
| temperature | no | NULL | Numeric or NULL. Sampling temperature, one non-negative number. NULL (default) sends no temperature field, so the provider's own default applies, as before this argument existed. A low value (e.g. 0.2) makes repeated calls on one prompt agree more often, which matters for a judgement that is re-asked or cached; it does not make them identical. Providers differ in the range they accept (Anthropic 0-1, OpenAI-compatible 0-2), and some current models reject the parameter outright: the provider then returns HTTP 400 (for example "temperature is deprecated for this model") and call_api() stops with that message. Leave it NULL unless the model accepts it. |

**Value:** A length-1 character string containing the model's response text. The following attributes are attached: '"model"' The resolved model identifier. '"provider"' The provider name used. '"tokens"' A named list with elements 'input' and 'output' (integers) giving the token counts reported by the provider. Both are 'NA_integer_' when the provider does not return usage information. Stops on any non-200 HTTP status with a provider-specific error message.

#### Details

Individual provider functions (call_anthropic_api, call_gemini_api, etc.) are thin wrappers around this function, useful directly or as llm_fn arguments.

Adding a new provider: Any provider that implements the OpenAI Chat Completions API can be added for the current session with register_provider. The function then dispatches via the openai_compat handler automatically.

Ollama quality note: Local Ollama models vary substantially in their ability to produce the structured JSON and CSV output that TaxaID functions expect. Results are less reliable than cloud providers, especially for obscure taxa. A warning is emitted when Ollama is selected.

Using as llm_fn: call_api is the default llm_fn throughout the TaxaID ecosystem. Individual provider functions can still be passed as llm_fn for explicit provider control:


```

# Use Gemini for a specific call prompt_api(prompt, llm_fn = call_gemini_api)

# Use a fast model for a batch task prompt_api(prompt, llm_fn = function(p, ...) call_api(p, tier = "fast"))

# Set session default to OpenAI options(TaxaID.provider = "openai") ```

Data sensitivity: Prompts sent to cloud LLM providers (Anthropic, Google, OpenAI, Azure) are transmitted over the internet and processed on third-party servers. Do not include sensitive, confidential, personally identifiable, or embargoed information in prompts. TaxaID functions pass taxon names, ecological summaries, and methods text -- review prompts before calling when working with pre-publication data. Use provider = "ollama" for fully local inference when data sensitivity is a concern.

### call_azure_openai_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), endpoint = NULL, max_completion_tokens = 16000L, api_key = Sys.getenv("AZURE_OPENAI_API_KEY"))

Call the Azure OpenAI API with a Single Prompt String

Low-level provider function: submits one plain character string to an Azure OpenAI Chat Completions endpoint and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Azure deployment name, e.g. "gpt-5.1". Default NULL resolves to the latest available deployment for tier via list_models. Specify an exact name to pin for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast", "mid" (default), or "top". For Azure, all tiers currently map to the same DOI deployment; the param is accepted for interface consistency. |
| endpoint | no | NULL | Character. Full deployment URL override, for callers that already have one. When provided, the deployment name is extracted from the URL path and the host is used to override the default DOI endpoint. Default NULL builds the URL from the registry template and the resolved model name. |
| max_completion_tokens | no | 16000L | Integer. Maximum tokens in the response (default 16000). Azure o-series models use this field name instead of max_tokens; handled automatically via the registry. |
| api_key | no | Sys.getenv("AZURE_OPENAI_API_KEY") | Character. Azure OpenAI API key. Defaults to the AZURE_OPENAI_API_KEY environment variable. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status.

#### Details

llm_fn usage:


```

# Direct use (default DOI endpoint) screen_pdf_structure(pdf_content, llm_fn = call_azure_openai_api) prompt_api(prompt, llm_fn = call_azure_openai_api)

# Non-default endpoint via closure my_azure <- function(p, ...) call_azure_openai_api(p, endpoint = "https://...") prompt_api(prompt, llm_fn = my_azure) ```

#### Department of the Interior (DOI) employees only

The default endpoint (api-dev.ai.doi.net) is an internal DOI service. Access requires an active connection to a DOI computer system or the DOI VPN. Calls from outside the DOI network will fail with a connection error. The AZURE_OPENAI_API_KEY must be obtained through DOI IT channels.

### call_gemini_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), max_tokens = 16000L, api_key = Sys.getenv("GEMINI_API_KEY"))

Call the Google Gemini API with a Single Prompt String

Low-level provider function: submits one plain character string to the Google Gemini generateContent API and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Exact Gemini model identifier, e.g. "gemini-2.5-flash". Default NULL resolves to the latest model for tier via list_models. Specify an exact model to pin a version for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast" (cheapest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. |
| max_tokens | no | 16000L | Integer. Ceiling on the tokens the model may produce (default 16000). A cap, not an allocation, so a generous value costs nothing extra; it is generous because a reasoning model spends part of the budget thinking before it writes, and a cap sized for the visible answer alone returns a response with no text in it. Sufficient for most taxonomy and habitat prompts. Increase for longer outputs (e.g., large species lists). Higher values increase API cost. |
| api_key | no | Sys.getenv("GEMINI_API_KEY") | Character. Google AI Studio API key. Defaults to the GEMINI_API_KEY environment variable. Get a free key at https://aistudio.google.com/apikey and add GEMINI_API_KEY=AIza... to ~/.Renviron. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status or safety block.

#### Details

Free tier: The Gemini API offers a genuinely free tier through Google AI Studio with no credit card required. Rate limits apply (requests per minute and per day vary by model). See https://ai.google.dev/gemini-api/docs/rate-limits.

llm_fn usage:


```

# Direct use screen_pdf_structure(pdf_content, llm_fn = call_gemini_api) prompt_api(prompt, llm_fn = call_gemini_api)

# Non-default model via closure my_gemini <- function(p, ...) call_gemini_api(p, model = "gemini-2.5-flash") screen_pdf_structure(pdf_content, llm_fn = my_gemini) ```

### call_ollama_api(prompt_str, model = "llama3.2", max_tokens = 16000L, base_url = "http://localhost:11434")

Call a Local Ollama Model with a Single Prompt String

Low-level provider function: submits one plain character string to a locally running Ollama instance and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Completely free - no API key or internet connection required after model download. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | "llama3.2" | Character. Ollama model name as listed by ollama list in Terminal. Default "llama3.2". Pull a model before first use: ollama pull llama3.2. Browse available models at https://ollama.com/library. Capable options for Apple Silicon: "llama3.1:8b", "mistral", "gemma3:12b", "qwen2.5:14b". |
| max_tokens | no | 16000L | Integer. Ceiling on the tokens the model may produce (default 16000). A cap, not an allocation, so a generous value costs nothing extra; it is generous because a reasoning model spends part of the budget thinking before it writes, and a cap sized for the visible answer alone returns a response with no text in it. Behaviour is model-dependent; some models may ignore this setting. |
| base_url | no | "http://localhost:11434" | Character. Base URL of the Ollama server. Default "http://localhost:11434". Change only if running Ollama on a different host or port. |

**Value:** A length-1 character string containing the model's response text. Stops with a clear message if Ollama is not running or the model has not been pulled.

#### Details

One-time setup:

- Install Ollama from https://ollama.com

- In Terminal: ollama pull llama3.2

- Confirm with: ollama list

Ollama starts automatically on macOS after installation.

Output quality: Local open-weight models vary substantially in their ability to produce the structured JSON and CSV output that TaxaID functions expect. Results are less reliable than cloud providers, especially for obscure taxa. Recommended minimum for TaxaID tasks: qwen2.5:14b. A warning is emitted automatically.

llm_fn usage:


```

# Direct use (default model) screen_pdf_structure(pdf_content, llm_fn = call_ollama_api) prompt_api(prompt, llm_fn = call_ollama_api)

# Specific model via closure my_ollama <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b") screen_pdf_structure(pdf_content, llm_fn = my_ollama) ```

### call_openai_api(prompt_str, model = NULL, tier = c("mid", "fast", "top"), max_tokens = 16000L, base_url = "https://api.openai.com", api_key = Sys.getenv("OPENAI_API_KEY"))

Call the OpenAI Chat Completions API with a Single Prompt String

Low-level provider function: submits one plain character string to the OpenAI Chat Completions API and returns the model's response as a plain character string. Drop-in replacement for 'call_api' when used as the 'llm_fn' argument to any function that accepts one. Thin wrapper around 'call_api'.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt_str | yes |  | Character. A length-1 string containing the complete prompt to submit. |
| model | no | NULL | Character. Exact OpenAI model identifier, e.g. "gpt-4o-mini". Default NULL resolves to the latest model for tier via list_models. Specify an exact model to pin a version for reproducibility. |
| tier | no | c("mid", "fast", "top") | Character. Capability tier used when model = NULL: "fast" (cheapest), "mid" (balanced, default), or "top" (most capable). Ignored when model is specified. |
| max_tokens | no | 16000L | Integer. Ceiling on the tokens the model may produce (default 16000). A cap, not an allocation, so a generous value costs nothing extra; it is generous because a reasoning model spends part of the budget thinking before it writes, and a cap sized for the visible answer alone returns a response with no text in it. Sufficient for most taxonomy and habitat prompts. Increase for longer outputs (e.g., large species lists). Higher values increase API cost. |
| base_url | no | "https://api.openai.com" | Character. Base URL of the API endpoint. Default "https://api.openai.com" (OpenAI). Any OpenAI-compatible API can be used by changing this URL -- see Details. When using a non-default URL, register the provider with register_provider to enable automatic tier resolution, or specify model explicitly. |
| api_key | no | Sys.getenv("OPENAI_API_KEY") | Character. API key for the provider. Defaults to the OPENAI_API_KEY environment variable for the standard OpenAI endpoint. For alternative providers, pass the key directly or via Sys.getenv("MY_KEY_VAR") in a closure. |

**Value:** A length-1 character string containing the model's response text. Stops on any non-200 HTTP status.

#### Details

Pricing note: OpenAI requires a paid account (or expiring $5 trial credits for new accounts). There is no ongoing free API tier. gpt-4o-mini is the most economical capable model.

OpenAI-compatible providers: Many providers implement the OpenAI Chat Completions API. Use base_url to reach them with a single function, or use register_provider for automatic tier resolution:


```

# xAI Grok -- specify model explicitly Sys.setenv(XAI_API_KEY = "xai-...") my_grok <- function(p, ...) call_openai_api(p, model = "grok-3-mini", base_url = "https://api.x.ai", api_key = Sys.getenv("XAI_API_KEY") ) options(TaxaID.llm_fn = my_grok)

# Or register for automatic tier resolution: register_provider("xai", "XAI_API_KEY", "https://api.x.ai", fallback_models = list(fast = "grok-3-mini", mid = "grok-3", top = "grok-3") ) ```

llm_fn usage:


```

# Direct use screen_pdf_structure(pdf_content, llm_fn = call_openai_api) prompt_api(prompt, llm_fn = call_openai_api)

# Non-default model via closure my_openai <- function(p, ...) call_openai_api(p, model = "gpt-4o") screen_pdf_structure(pdf_content, llm_fn = my_openai) ```

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

**Value:** A data frame with one row per queried taxon (genus or higher rank): group Character. Taxon name (genus/family/order). gbif_key Integer. GBIF usageKey used for the query. total_described Integer. Number of accepted species in GBIF backbone. in_reference Integer. Species found in 'match_species' (NA if 'match_species' not provided). n_missing Integer. 'total_described - in_reference' (NA if 'match_species' not provided). missing_species List-column. Character vector of missing species names per genus (empty list if 'match_species' not provided or genus is complete). described_species List-column. Character vector of all described species names per genus. status Character. '"complete"', '"singleton_missing"', or '"incomplete"' (NA if 'match_species' not provided). The complete species list across all queried taxa is available as 'attr(result, "all_species")' (a flat character vector).

#### Details

For rank = "genus", the function makes one GBIF API call per genus (rgbif::name_usage(key, data = "children")). For higher ranks (family, order), it first retrieves child genera, then recurses into each genus -- this can be slow for large families (e.g., Gobiidae with 300+ genera).

The status column classifies each genus by reference completeness:

- "complete": all described species are in the reference (n_missing == 0). H2 "unreferenced species" hypotheses should be suppressed.

- "singleton_missing": exactly one described species is missing (n_missing == 1). The H2 hypothesis can be named directly.

- "incomplete": multiple described species are missing (n_missing > 1). A generic H2 phantom is appropriate.

### change_backbone(input_df, input_col, old_backbone_label = "source_name", new_backbone_label = "translated_name", keep_unmatched = TRUE)

Translate Taxon Names Between Taxonomic Backbones

Post-processes the output of 'verify_taxon_names' to (1) rename the source and translated name columns with meaningful backbone labels, and (2) parse the pipe-delimited 'classification_path' and 'classification_ranks' columns into a wide-format taxonomy table (one column per rank: kingdom, phylum, class, etc.).

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A dataframe returned by verify_taxon_names, containing at minimum: user_supplied_name, matched_name, classification_path, and classification_ranks. |
| input_col | yes |  | Character. The name of the column in input_df holding the original (source backbone) names. Typically "user_supplied_name". |
| old_backbone_label | no | "source_name" | Character. The label to assign to the source-name column in the output (e.g., "NCBI" or "GBIF"). Default is "source_name". |
| new_backbone_label | no | "translated_name" | Character. The label to assign to the translated-name column in the output (e.g., "GBIF" or "NCBI"). Default is "translated_name". |
| keep_unmatched | no | TRUE | Logical. When TRUE (the default), names for which the target backbone returns no match are retained by copying the original source name into the translated-name column rather than leaving it NA. Set to FALSE to keep NA for unmatched names instead. |

**Value:** A dataframe with: '<old_backbone_label>' Original names (renamed from 'input_col'). '<new_backbone_label>' Translated names (renamed from 'matched_name'). 'backbone_matched' Logical. 'TRUE' when the target backbone returned a genuine match; 'FALSE' when no match was found (the source name was retained due to 'keep_unmatched = TRUE', or left 'NA' when 'keep_unmatched = FALSE'). Always 'TRUE' when 'keep_unmatched = FALSE' and the backbone matched. 'score' Match confidence score from 'verify_taxon_names'. Review rows with low scores before using the translation downstream. 'verified' Logical API-success flag from 'verify_taxon_names'. kingdom, phylum, ... Wide-format rank columns parsed from 'classification_path'. Column names are the rank labels returned by the backbone (typically lowercase Linnaean ranks). Ranks absent for a given row are 'NA'. The intermediate columns 'classification_path' and 'classification_ranks' are dropped after parsing.

#### Details

This function does not call any API. The backbone translation is performed by the upstream verify_taxon_names() call -- this function only reshapes and labels the result. The backbone ID passed to verify_taxon_names() determines which backbone the names are translated into; old_backbone_label and new_backbone_label are purely descriptive column labels in the output.

When keep_unmatched = TRUE (the default), names that have no match in the target backbone (matched_name is NA) are retained by copying the original source name into the translated-name column. This prevents downstream data loss when a backbone does not recognise a valid taxon (e.g., a recently synonymised name, a hybrid, or a regional name absent from NCBI). A message reports how many names were retained this way. Rank columns for unmatched rows remain NA -- callers that need a rank label for these rows (e.g., for taxon_name_rank) should coalesce with an appropriate fallback after the join.

Typical two-step usage:


```

# Step 1: verify_taxon_names() does the translation (backbone_id = 11 is GBIF). # Step 2: change_backbone() labels and reshapes the result. verify_taxon_names(ncbi_names, backbone_id = 11) |> change_backbone( input_col = "user_supplied_name", old_backbone_label = "NCBI", new_backbone_label = "GBIF" )

# To translate back (GBIF -> NCBI), call verify_taxon_names() again with the # NCBI backbone ID (4), then pipe to change_backbone() with swapped labels. ```

The score and verified columns from verify_taxon_names are retained in the output so you can inspect translation quality before using the result downstream.

### check_lineage_agreement(declared, returned, ignore = c("cellular organisms", "Eukaryota", "Bacteria", "Archaea", "Viruses",      "Metazoa", "Viridiplantae", "Fungi"))

Check whether a returned lineage agrees with a declared one

A cheap, no-API-call post-fetch guard: given what a caller DECLARED about a taxon's own higher-rank lineage (e.g. from their own match object) and what a name-based fetch ACTUALLY RETURNED for it, decides whether the two are the same organism reclassified (a benign revision - accept) or two different organisms sharing a name (a homonym - reject). Both present identically as "the returned lineage disagrees with mine"; the operative test is not whether any one rank matches exactly, but whether the disagreement is CONTAINED within some shared higher clade at all. See ...

| Param | Required | Default | Doc |
|---|---|---|---|
| declared | yes |  | Character vector. One element per row: the caller's own known higher-rank lineage terms for that row, pipe- or semicolon-delimited (e.g. "Rhodophyta\|Florideophyceae\|Ceramiales"). |
| returned | yes |  | Character vector, same length as declared. The corresponding lineage actually returned by the fetch being checked, in the same delimited form. |
| ignore | no | c("cellular organisms", "Eukaryota", "Bacteria", "Archaea", "Viruses",      "Metazoa", "Viridiplantae", "Fungi") | Character vector of lineage terms that never count as agreement, case-insensitive. The default holds the roots that every lineage shares ("cellular organisms", "Eukaryota", "Bacteria", "Archaea", "Viruses") and the kingdom-level groups a cross-phylum homonym still shares ("Metazoa", "Viridiplantae", "Fungi"). Without this, a full NCBI-style lineage on both sides would return "agrees" for a red alga and a bat on "Eukaryota" alone. Compare lineages scoped below the shared root; pass character(0) to count every term. |

**Value:** Character vector, same length as 'declared', one of '"agrees"' (at least one shared term outside 'ignore' - same clade, whether an exact match or a benign revision), '"disagrees"' (both sides have real terms and share none - a likely homonym), or '"unknown"' (one or both sides had nothing to compare after 'ignore').

#### What a disagreement means

Treat "disagrees" as a review candidate, not a filter. A disagreement at family level alone cannot separate a homonym from a benign reclassification (Modiolus Mytilidae -> Modiolidae is the same mussel), and on a real COI reference set of 4,638 genera only about 12 of 78 family-level disagreements were homonyms. The test that separates them is whether the disagreement is contained within a shared higher clade, which needs ranks above family on both sides. Inspect the candidates, or supply lineages that reach phylum and class.

A homonym can also present as zero results: a name that resolves to the wrong NCBI node may legitimately return nothing, and an empty result gives this function nothing to compare. After a fetch, check which requested taxa returned no sequences at all, not only which returned something odd.

### check_taxaid_manifest(path, packages = NULL, on_mismatch = c("error", "warning", "message", "silent"))

Check the Installed TaxaID Code Against a Recorded Manifest

Compares the library this session is using against a manifest written by 'write_taxaid_manifest()', and by default *errors* on any difference. Put it in a workflow preamble so drift stops a run at the top rather than producing results nobody can attribute afterwards.

| Param | Required | Default | Doc |
|---|---|---|---|
| path | yes |  | Path to a manifest written by write_taxaid_manifest(). |
| packages | no | NULL | Restrict the comparison. Default: every package named in the manifest or in the standard TaxaID set. |
| on_mismatch | no | c("error", "warning", "message", "silent") | One of "error" (default), "warning", "message", "silent". |

**Value:** Invisibly, a list with 'ok', 'missing', 'changed', 'extra' and 'manifest' (the freshly built one).

#### What it reports, and why absence comes first

- MISSING: In the manifest, not installed now. Reported first and deliberately: a checker that only compares what it finds on BOTH sides cannot report what is absent, and a package that has silently vanished from the library is the most dangerous of the three -- calls to it fail late, or resolve to a different namespace.

- CHANGED: Installed, but the code hash differs -- someone reinstalled between the manifest and this run.

- EXTRA: Installed now, absent from the manifest; usually a manifest written before a package existed.

Version and Built differences are shown but never fail on their own: rebuilding identical source moves Built and changes nothing that matters, and every TaxaID package sits at 0.1.0 so the version is silent by construction. The code hash is the signal.

### clean_taxon_names(name_vec, remove_abbr = NULL, strip_modifiers = NULL)

Extract and Clean Taxon Names from a Character Vector

Cleans a character vector of taxon names by normalising whitespace, removing 'NA's, removing names that do not begin with a capital letter (e.g., codes, placeholders, artefacts), converting underscore-separated binomials to space-separated ones (e.g. '"Corallina_officinalis"' -> '"Corallina officinalis"', as produced by Jonah Ventures and SILVA pipelines), trimming abbreviated second words (sp., spp., etc.) to genus-only, stripping bracket artefacts, and stripping a single known leading breeding/ploidy-manipulation modifier word (e.g. '"androgenetic Carassius auratus"' -> '"Carassius ...

| Param | Required | Default | Doc |
|---|---|---|---|
| name_vec | yes |  | A character vector (or factor) of taxon names. |
| remove_abbr | no | NULL | A character vector of second-word tokens that flag the name as genus-only (the abbreviation is dropped). Defaults to a standard list of common abbreviations and placeholder terms. Pass a custom vector to extend or replace the default list. |
| strip_modifiers | no | NULL | A character vector of known leading modifier words (case-insensitive, matched against the FIRST whitespace-delimited token only, and only ever removed once per name -- never a repeated strip). Defaults to a curated list of real breeding/ploidy-manipulation terms found on real GenBank hybrid-cross records ("androgenetic", "gynogenetic", "autodiploid", "autotriploid", "autotetraploid", "allodiploid", "allotriploid", "allotetraploid", "diploid", "triploid", "tetraploid", "polyploid"). Deliberately does NOT include uncertainty-hedge words ("possible", "putative", "probable", "tentative", "presumed", etc.) or "hybrid"/"unidentified" themselves -- those genuinely change what the name means (a hedge should keep failing the capital- letter filter below, not get silently rescued into a confident binomial; "hybrid X x Y" with no named first parent has no real maternal-parent identity to recover). Pass a custom vector to extend or replace the default list; character(0) disables this step entirely. |

**Value:** A character vector the same length as 'name_vec'. Names that do not start with a capital letter, are 'NA', or consist only of an abbreviation are set to 'NA'. An R attribute 'collapsed_to_genus' (logical, same length) is also set: 'TRUE' for a row that HAD a real second token (an epithet-shaped string, e.g. an open-nomenclature label like '"Ictalurus cf. pricei USON-01120-1"') which was dropped because it matched 'remove_abbr' or was too short - i.e. this row's output is a genus-only name that used to be (or claimed to be) something finer. 'FALSE' for a row that was already genus-only to begin with, or that was rejected outright ('NA' output). Added so a caller building 'taxon_name'/'taxon_name_rank' pairs from this function's output can correct 'taxon_name_rank' to '"genus"' alongside the name itself - see 'convert_taxonomy_backbone''s own not-found fallback path for the motivating real bug this closes (a restored candidate's 'taxon_name_rank' silently staying '"species"' after its name was correctly collapsed to genus-only). Two further attributes, same length: 'name_qualifier' is '"cf."' or '"aff."' when the name carried that open-nomenclature qualifier (leading, as in '"cf. Laternula"', or after the genus, as in '"Laternula cf. marilina"'), else 'NA'. A qualified name returns its GENUS, with 'collapsed_to_genus = TRUE': the qualifier means the species is not asserted, and the attribute keeps a qualified genus distinguishable from an asserted one. 'clean_reason' names a structural change, else 'NA': '"subgenus_dropped"' (a parenthesised subgenus after the genus, '"Allodia (Brachycampta) lugens"' -> '"Allodia lugens"'; the subgenus is never returned as an epithet), '"qualifier"', '"hybrid_congeneric"' (a hybrid formula whose parents share a genus returns that genus) or '"hybrid_intergeneric"' (parents in different genera return 'NA': neither parent is the organism). A named nothospecies ('"Mentha x piperita"') is not a formula.

#### Details

This function operates on a plain character vector, not a dataframe. Common patterns for dataframe workflows:


```

# Pattern 1 -- extract a unique vector for API calls: name_vec <- df |> dplyr::pull(taxon_name) |> clean_taxon_names()

# Pattern 2 -- clean the column in place: df <- df |> dplyr::mutate(taxon_name = clean_taxon_names(taxon_name)) ```

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

**Value:** A data frame with one row per element of 'common_names': 'common_name' Input common name (character). 'scientific_name_llm' Scientific name suggested by the LLM, or 'NA' if ambiguous or unknown. 'scientific_name_verified' Backbone-verified scientific name (from 'verify_taxon_names'), or 'NA' if verification failed or 'verify = FALSE'. 'backbone_id' Backbone used for verification (integer). 'verified' Logical; 'TRUE' if 'verify = TRUE' and the backbone returned a match. 'notes' Character; LLM explanation for ambiguous or unresolved names.

#### Details

Common names are inherently ambiguous: "Robin" means Turdus migratorius in North America but Erithacus rubecula in Europe; "Hawk" has no unambiguous species referent. Supplying taxon_group and location resolves most ambiguities. The function sends all names in a single LLM call and returns one row per input name.

When a name is too ambiguous to resolve, the LLM returns NA for scientific_name_llm with an explanatory notes entry. When verify = TRUE and backbone verification fails (name not found or spelling inconsistent), scientific_name_verified is NA and verified is FALSE. Returning the unverified LLM suggestion in a separate column allows the user to inspect and decide rather than silently discarding potentially useful information.

### create_taxon_names(input_df, rank_system = NULL)

Create Most Specific Taxon Name Column

Takes a dataframe with separate taxonomic rank columns and adds two new columns: 'taxon_name' (the value from the most specific non-NA rank) and 'taxon_name_rank' (the name of that rank, in lowercase). Column matching is case-insensitive, so rank columns named "Kingdom" or "KINGDOM" match the same as "kingdom".

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A data frame containing taxonomic rank columns. |
| rank_system | no | NULL | A character vector of column names (any case) listing taxonomic ranks from broadest to most specific, e.g. c("kingdom", "phylum", "class", "order", "family", "genus", "species"). The function walks this vector from right to left and returns the first non-empty value. If NULL (the default), auto-detected from column names via detect_ranks. |

**Value:** The input data frame with two columns appended: taxon_name The most specific non-NA rank value for each row. taxon_name_rank The rank label (lowercase) corresponding to 'taxon_name'. 'NA' when all ranks are 'NA'.

#### Details

If all rank columns are NA for a row, both output columns are NA silently.

### default_sampling_scheme()

Default Sampling-Group Classification Scheme

Returns the package's default sampling-group scheme: an ORDERED list of rules (first-match-wins, exactly like the 'dplyr::case_when()' it replaces) that classifies a taxon's kingdom/phylum/class/order into one of ten detection-process groups (encoded as eleven ordered rules - '"parasites"' has two, by design, since it is reached via two unrelated clauses), or a catch-all. See Details for clause-specific rationale.

(no parameters)

**Value:** A sampling-group scheme object; see Shape above.

#### Shape

The returned object is a list with three elements:

- rules: An ORDERED list of rules. Each rule is list(group = "<name>", when = list(<clause>, <clause>, ...)). The when clauses are OR'd together (a rule fires if ANY clause matches); a clause is a named list mapping a rank (kingdom/phylum/class/order) to a character vector of values, and the ranks WITHIN one clause are AND'd together. A literal NA as a clause's value for a rank means "this rank is missing" (is.na()), not "match nothing" -- this is what lets the class-less-Chordata fish clause (phylum == "Chordata" AND class missing) be expressed faithfully. Example:


```

list( group = "fishes", when = list( list(class = c("Actinopteri", "Elasmobranchii", ...)), list(phylum = "Chordata", class = NA) ) )

```

- catch_all: The group name used when no rule matches ("macroinvertebrates").

- rules: ...and note that a rule may read a rank outside assign_sampling_group()'s rank_cols -- the Hydrozoa rules read family. Such a column is read AS SUPPLIED: with harmonise = TRUE only kingdom, phylum, class and order are rewritten to the backbone, so a family clause still matches the caller's own spelling. A rank the table does not carry means its clauses cannot fire: supply no family column and Porpitidae and Velellidae fall through to the hydroid-order rule and come out as "macroinvertebrates" rather than "zooplankton". assign_sampling_group(verbose = TRUE) names any such rank once.

- animal_phyla: Character vector of animal phylum names, used by assign_sampling_group when a catch-all row's KINGDOM cannot decide animal from non-animal (a domain label such as "Eukaryota", or no usable value) and the phylum must. A closed set, which is what lets "not in this list" be a confident non-animal conclusion instead of an open-ended list of everything that is not an animal.

- kingdom_guard_vocabulary: Character vector of kingdom values considered "animal" for the kingdom guard (see assign_sampling_group's kingdom_guard argument): c("Animalia", "Metazoa").

#### First-match-wins contract

rules is evaluated top to bottom, exactly like a dplyr::case_when(): a row is assigned to the FIRST rule whose when clauses match, and every later rule is skipped for that row -- even if a later rule would also have matched. This is a real, load-bearing property of the original classifier (e.g. a taxon that matches both a specific rule and a later, broader one always takes the specific one), and assign_sampling_group preserves it exactly.

#### Class-level vs. phylum-level rules

Two traps this scheme's clauses are written to avoid:

- Bacillariophyceae (diatoms) -> "phytoplankton". Trap: GBIF places diatoms in phylum Ochrophyta, the SAME phylum as the kelps/rockweeds (Phaeophyceae, classified as "macroalgae" above). A phylum-level rule for either group would be wrong in one direction or the other -- it would either exclude the diatoms or admit the kelps into the wrong group. This MUST be a class-level rule, and it is: the diatom clause names class = "Bacillariophyceae" only, never phylum = "Ochrophyta".

- Copepoda -> "zooplankton". GBIF's current backbone names this class "Hexanauplia"; NCBI's backbone names it "Copepoda". Both spellings are added to the SAME zooplankton clause, so the classifier works whichever backbone the input taxonomy came from. "Copepoda" is also found live in real GBIF-backbone occurrence data, not only in NCBI match objects, which is why it is added to the rule directly rather than only handled via harmonise = TRUE.

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

#### Details

Interaction model:

- Drag any numbered circle to move that vertex.

- Add Point inserts a new draggable vertex at the midpoint of the current longest side. Drag it to the desired position. There is no limit on the number of vertices.

- Remove Last Point removes the most recently added vertex. The initial corners cannot be removed this way.

- The WKT string updates live in the toolbar so you can inspect it before clicking Done.

Tile choice: For marine / coastal studies use the default "Esri.OceanBasemap" (shows bathymetry and shelf). For terrestrial or freshwater studies "OpenStreetMap" or "Esri.WorldTopoMap" may be clearer.

Non-interactive use: For scripted or non-interactive workflows use make_bbox_wkt instead.

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
| description | no | NULL | Character. Brief study context to guide the LLM (e.g., "eDNA metabarcoding of coral reef fish at Palmyra Atoll using MiFish 12S primers", or "acoustic point-count survey of frog calls in a coastal wetland"). Default NULL. Ignored when context is provided (uses context$study_description). |
| context | no | NULL | A report_context object from build_report_context. Provides structured facts (study description, parameters, statistics, citations) that the LLM must use as ground truth. When provided, overrides description. Default NULL. |
| audience | no | "journal" | Character. Target audience: "journal" (default) for peer-reviewed publication style, "technical" for a methods appendix with parameter details, or "brief" for a short summary. |
| llm_fn | no | getOption("TaxaID.llm_fn", call_api) | Function. LLM provider function with signature function(prompt_str, ...) -> character(1). Default getOption("TaxaID.llm_fn", call_api) -- the ecosystem-wide auto-detected provider (see call_api), falling back to call_api itself if the option is unset. |
| max_code_lines | no | 300L | Integer. Maximum number of code lines to include in the prompt. Long scripts are truncated with a note. Default 300L. |
| verbose | no | FALSE | Logical. Print progress messages. Default FALSE. |

**Value:** A character string containing the drafted methods text. Printed to the console via 'cat()' and returned invisibly.

#### Details

The function sends the R code to the LLM with instructions to:

- Describe the analysis workflow in past tense

- Note key parameters and their values

- Use appropriate scientific language for the audience

- Avoid reproducing code; describe what was done conceptually

- Not report findings or summary statistics -- these belong in the Results section (use draft_results_text)

- Flag any analysis steps that used LLM-generated data, with a caveat about stochastic output

Code comments are treated as facts. If the code contains comments like "# 70 paired-end MiSeq samples" or "# DADA2 denoised with default parameters", the LLM will incorporate this information into the methods text. Make sure code comments are accurate before passing the script. To provide verified facts that override inferences from code comments, use the context parameter.

Statistics bleed guard. When a context is provided, its statistics field (sample sizes, resolution rates, etc.) is shown to the LLM for accuracy checking only. The LLM is explicitly instructed not to report these numbers in the methods text. If you find statistics appearing in the methods output, they likely came from code comments rather than the context; review and clean the code comments, or use a more targeted code excerpt.

LLM stochasticity. Because the output is generated by an LLM, it will vary slightly between runs. The output is a starting point for editing, not a final manuscript. Always review for accuracy.

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

#### Details

For each named object, the function extracts:

- Data frames: dimensions, column names and types, summary(), and the first few rows

- Lists: str() output (truncated)

- Numeric vectors: summary() and length

- Other objects: print() output (truncated)

These summaries are sent to the LLM with instructions to write a results section highlighting key findings, sample sizes, and summary statistics.

When a context object is provided, its statistics and facts are included as verified ground truth. The LLM is instructed to use these numbers exactly rather than computing its own from the data summaries.

LLM-derived data caveat. If the data objects contain values that were generated by an LLM (e.g., habitat classifications, range assessments), the LLM is instructed to note this and include a brief caveat about stochastic output. You can also add an explicit note in context$facts (e.g., facts = list(llm_role = "habitat classification via Claude")).

LLM stochasticity. The output is generated by an LLM and will vary between runs. Always review for accuracy. The output is a starting point for editing, not a final manuscript.

### escalate_taxonomic_rank(taxon_name, current_rank, rank_system = standard_ranks, max_levels = 2L, backbone_id = 4L, fallback_backbone_id = 11L, verbose = TRUE, decisions = NULL)

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
| decisions | no | NULL | Forwarded verbatim to verify_taxon_names()'s own decisions parameter (relevant only when backbone_id = 4) -- this function grows no prompt or resolution logic of its own for an NCBI name collision. |

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

**Value:** A tibble, one row per unique non-'NA' input name: 'taxon_name' The name as supplied (whitespace trimmed). 'in_worms' Logical. A trusted match was found. 'aphia_id', 'accepted_name', 'accepted_aphia_id', 'taxonomic_status', 'worms_rank' From the representative record (the first 'accepted' match, else the first match). 'match_type' '"exact"', or the rejected match type(s) when 'fuzzy_rejected' is 'TRUE'. 'n_matches' Records retained for this name. 'fuzzy_rejected' WoRMS returned only non-exact matches and 'accept_fuzzy = FALSE', so none were used. 'is_marine', 'is_brackish', 'is_freshwater', 'is_terrestrial' Logical, *multi-label and possibly 'NA'*. 'NA' means WoRMS has not assessed that realm, which is not the same claim as 'FALSE'. 'marine_scope' Logical, *never 'NA'*. 'TRUE' when any retained match is marine or brackish. This is the column to hand to a detection-level scope filter. 'habitat_unassessed' In WoRMS but all four flags 'NA' - dropped for lack of evidence rather than on evidence. Counted separately and reported. 'worms_ambiguous', 'habitat_conflict' More than one retained match; and those matches disagreeing about 'marine_scope'. 'ncbi_id' Character NCBI taxon id, or 'NA'. A curated crosswalk, versus the live one computed by 'verify_taxon_names(backbone_id = 4)' / 'change_backbone'. 'wrims' Logical. Any WoRMS distribution record with 'establishmentMeans' of "Alien". Derived, not a WoRMS field - see Details of 'extras'. 'kingdom', 'phylum', 'class', 'order', 'family', 'genus' WoRMS classification of the representative record. Attributes on the result, always present (the 'count_failures' pattern), so a quiet run still leaves the residue inspectable: '"n_not_in_worms"' / '"not_in_worms"', '"n_fuzzy_rejected"' / '"fuzzy_rejected_taxa"', '"n_habitat_unassessed"' / '"habitat_unassessed_taxa"', '"n_habitat_conflict"' / '"habitat_conflict_taxa"', '"n_request_failed"' / '"request_failed_taxa"' (names whose request errored - these are *not* cached and are *not* absences), and '"worms_query"' with the settings used.

#### Details

Why this is not the habitat lookup you already have. TaxaHabitat::build_habitat_lookup() asks an LLM to choose ONE of Marine / Estuarine / Freshwater / Terrestrial. Intertidal foragers that stand on rock come back Terrestrial -- the black oystercatcher (M 0.40 / T 0.50), sanderling (0.20 / 0.50), black turnstone (0.30 / 0.60) and whimbrel all do, and 381 of 578 PtConception birds go the same way. WoRMS records the oystercatcher as marine and terrestrial. The two sources answer different questions and neither replaces the other.

The filter rule is "keep if marine OR brackish", never "drop if terrestrial". Every shorebird above is terrestrial = TRUE. Diadromous fish are handled by the same rule without a special case: Oncorhynchus mykiss and Alosa sapidissima are both marine = TRUE, brackish = TRUE, freshwater = TRUE, terrestrial = FALSE. The marine_scope column applies this rule and is never NA.

Apply the verdict at detection level (an ESV/ASV for sequence data, a per-image or per-recording candidate ID otherwise), not taxon level. Filtering candidates within an observation strips hypotheses out of a candidate set and forces the read onto whichever ones survive. Drop an observation only when NO candidate is in scope; an observation with any marine candidate keeps its whole candidate set, out-of-scope competitors included. See the examples.

This is a different axis from a taxonomic scope filter, and they compose. A taxonomic filter ("is this a fish / macroinvertebrate / macroalga?") keeps terrestrial snails, freshwater mussels, freshwater annelids and freshwater algae, because those are Gastropoda / Bivalvia / Polychaeta / Ulvophyceae wherever they live. Verified here: Cornu aspersum (garden snail) and Lumbricus terrestris are marine = FALSE, so WoRMS cuts them. Conversely WoRMS cannot cut a marine copepod and a taxonomic filter can. Report the saving from both.

What happens to non-marine taxa is the caller's decision, and it should not be silent deletion. Human / pig / cow / chicken DNA is a lab-contamination signal, and out-of-scope counts are a data-quality diagnostic. Cut these taxa from the prior and likelihood path but retain the rows and counts -- a scope_excluded table and a line in the pipeline report.

Two rules protect against silent loss of a real detection. A fuzzy match is not treated as a match unless accept_fuzzy = TRUE: WoRMS will resolve "Mytilus edulus" phonetically to Mytilus edulis, and the same machinery will hand a terrestrial homonym's flags to a marine name. Rejected fuzzy matches are reported in fuzzy_rejected, not hidden. And homonyms are ORed rather than resolved: "Ficus" is both a marine gastropod genus (AphiaID 205605, marine) and the fig genus (447837, not marine), so marine_scope is TRUE if any retained match is marine or brackish, with worms_ambiguous and habitat_conflict marking the case for review.

Absence is part of the filter, and is also its main risk. Cervus elaphus and Zea mays are not in WoRMS at all, so there is no threshold to tune. But a genuinely marine taxon missing from the register is cut the same way. Every absent name is returned in the "not_in_worms" attribute -- read it before trusting a run. Absence is a weaker filter than intuition suggests: Homo sapiens (1455977), Sus scrofa (1469456), Bos taurus (1506698), Canis lupus (1506689) and Gallus gallus (1463738) are all in the register. They are cut on their flags (marine = FALSE / NA, terrestrial = TRUE), not on absence.

Names are used as supplied, apart from whitespace trimming. Pass names that have already been through clean_taxon_names if the source carries open-nomenclature or voucher labels; slash labels and "Genus sp." will not match.

### fill_higher_ranks(taxon_names, input_rank = NULL, local_sources = list(), fill_ranks = "family", record_source = FALSE, backbone_id = 4L, fallback_backbone_id = 11L, verbose = TRUE, decisions = NULL, lineage = NULL)

Fill Higher Taxonomic Ranks from Local Data and Backbone APIs

Given a character vector of taxon names (typically species binomials), derives 'genus' (first word of the binomial) and looks up 'family' using a priority-ordered fallback chain:

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of taxon names (an empty vector returns a zero-row table with the usual columns). Binomial species names are expected; genus is extracted as the first word. Single-word names (genus only) are accepted and returned as-is in the genus column. |
| input_rank | no | NULL | Character vector or NULL (default). One rank per element of taxon_names (NA = unknown), e.g. the table's taxon_name_rank column. The backbone query asks the first word of each name, which for a species or a genus is its genus and is asked at rank genus. A name whose own rank is family, order, class, phylum or kingdom is a single word that is the whole name, and asking it at genus picks whatever genus shares the spelling (a class-rank Nuda resolved to a flagellate genus Nuda); given its rank here it is asked at that rank. A word that arrives at two coarse ranks is asked at genus with a message. NULL asks every word at genus. |
| local_sources | no | list() | List of data frames to consult before any API call. Each element must contain at least genus and the requested rank; elements lacking those columns are silently skipped. Sources are consulted in order and the first non-NA value for each genus wins. That precedence is the right policy when you have ranked your sources by authority, and it decides nothing useful when the genus name is a homonym -- Dilophus is a fly and a brown alga, Porella a bryozoan and a liverwort -- because the value it picks may then describe a different organism. So for a genus that maps to more than one value, the lookup is keyed on the taxon's OWN row in your sources instead: a value standing beside this exact name is a statement about this taxon, where a genus-keyed one is a statement about whatever else shares the name. Only those genera are treated this way -- where the genus is unanimous the two agree anyway, and preferring one row there would import that row's own errors. A genus with no row of its own to read keeps the precedence, and every genus that mapped to several values is REPORTED by name along with how it was settled. Read that message: it is the only signal that a filled value was a choice rather than a lookup. Measured on one real multi-marker study, 202 of 15,160 genus names in the sources mapped to more than one family; 74 of those genera reached the 3,489 taxa being filled, affecting 137 of them. Every one was resolved from its own row, changing 49 fills, and 63 of the 137 carried competing family circumscriptions for the same organism -- two backbones disagreeing about one fish, not a homonym -- which no lineage can arbitrate and which the precedence therefore still settles. |
| fill_ranks | no | "family" | Character vector of higher ranks to resolve. Default "family". Any rank label the backbone reports is accepted, e.g. c("family", "class"). "genus" is rejected (it is derived from taxon_names, not looked up) and so is "species". Each rank is resolved down the same chain and recorded in its own column. |
| record_source | no | FALSE | Logical. FALSE (default) returns only the taxon_name, genus and rank columns. TRUE adds one <rank>_source column per entry in fill_ranks, holding "local", "backbone_<id>", or NA where the rank was never resolved. It is off by default because TaxaAssign::join_priors() joins EVERY non-taxon_name column of its expansion_taxonomy argument onto the priors table, so an unwanted source column would travel into the posteriors. Turn it on when you want provenance, and drop the columns before passing the frame to join_priors(). |
| backbone_id | no | 4L | Integer. Primary backbone for API fallback. Default 4L (NCBI). Set NULL to skip the API entirely. |
| fallback_backbone_id | no | 11L | Integer. Secondary backbone used when backbone_id returns no match. Default 11L (GBIF). Set NULL or equal to backbone_id to skip. |
| verbose | no | TRUE | Logical. Print progress messages for API lookups. Default TRUE. |
| decisions | no | NULL | Forwarded verbatim to verify_taxon_names()'s own decisions parameter for every genus-level lookup this function makes (primary and fallback backbone alike, whichever is 4) -- this function grows no prompt or resolution logic of its own for an NCBI name collision. |
| lineage | no | NULL | Character vector or NULL (default). One lineage context per element of taxon_names (NA = none), a pipe-delimited string of ancestor names the caller already knows for the taxon (its GBIF phylum, the study's class). Forwarded, per genus, to verify_taxon_names(lineage =) on both backbones: it resolves an NCBI homonym rank alone cannot (two genus-rank nodes in different kingdoms) and rejects a fallback-backbone answer that contradicts it. The genus queries always carry input_rank = "genus". |

**Value:** A tibble with one row per element of 'taxon_names' (preserving duplicates and order), with columns: 'taxon_name' The original input name. 'genus' First word of 'taxon_name', EXCEPT when an API lookup resolved that genus to a backbone-flagged synonym at genus rank - in that case the backbone's own currently-accepted genus name is returned instead (see @section Genus correction below). Local-source-only lookups (no API call needed) always keep the locally-extracted genus unchanged. <rank> One column per entry in 'fill_ranks' (by default just 'family'), holding the looked-up value or 'NA' if unresolved. <rank>_source Only when 'record_source = TRUE': where that value came from - '"local"', '"backbone_<id>"', or 'NA'. A warning is issued, per rank, for any names that rank could not be resolved for after all fallbacks.

#### Details

Backbone queries are at genus level. verify_taxon_names() is called with the unique unresolved genera (not the full species names). This means a species absent from NCBI is still resolved provided its genus is present -- which covers the vast majority of cross-backbone synonym situations.

Column name conflicts in local sources (e.g. a source has both genus and Genus) are handled by tolower(names(...)) before joining.

#### Filling only where a backbone is silent

A rank is filled only where the backbone above it in the chain said NOTHING. A value the primary backbone supplied is never replaced by the fallback's, and a value already present is never overwritten. Silence and contradiction are different things and only the first is filled here.

This is the opposite emphasis from TaxaAssign::posterior_consensus()'s cross_phylum_eps, where the backbone WINS over a disagreeing input: GBIF makes Sipuncula a phylum in its own right, so a sipunculan row carrying phylum = "Annelida", class = "Sipuncula" is treated as a genuine cross-phylum conflict rather than reconciled. The two rules are consistent because they answer different questions. There, two sources disagree and the backbone is trusted; here, one source is silent and another is asked. Nothing in this function adjudicates a disagreement.

The motivating case is GBIF's treatment of the ray-finned fishes. GBIF returns kingdom|phylum|order|family|genus for them with no class entry at all -- its Actinopterygii/Actinopteri node is not an accepted backbone class -- so class comes back NA and a consensus keyed on class lands at phylum Chordata. NCBI supplies Actinopteri, and because GBIF is silent rather than contradictory, filling it is safe.

#### Homonyms, and what the agreement check does and does not cover

A bare genus name is not a key. GBIF carries a polychaete worm genus "Corallina" (Animalia|Annelida|Polychaeta|...) alongside the red algal genus NCBI resolves (Rhodophyta|Florideophyceae|...), and BOTH match at genus rank, so matched_rank cannot separate them.

Before a FALLBACK value is accepted the primary must have PLACED that genus, and the fallback's lineage must not contradict the primary's at phylum (or division); a rejected genus raises a warning naming it. A genus the primary could not place at all is refused rather than trusted -- that is not the same as the primary being silent about one rank, and it is when the fallback is least safe: NCBI refuses "Liparis" as ambiguous (a snailfish and an orchid), and GBIF resolves the same string to an insect genus, so trusting it would put class = "Insecta" on a fish. When no primary backbone is configured at all the fallback is the only source and is used as given. Coarser ranks are deliberately not compared: the backbones use different vocabulary for the same kingdom ("Metazoa" against "Animalia"), and finer ranks disagree routinely for the same organism (NCBI places Girella in Centrarchiformes, GBIF in Perciformes), so both produced false contradictions when tried.

The check cannot protect against a wrong PRIMARY backbone, which is authoritative by construction: query with backbone_id = 11 (GBIF) and "Corallina" resolves to class "Polychaeta" with nothing to compare it against. Choose the primary backbone for the group being resolved; the default (NCBI primary, GBIF fallback) answers all of the above correctly.

#### Genus correction

genus reflects the backbone's currently-accepted name whenever an API lookup resolves the locally-extracted genus to a taxonomic synonym at genus rank -- e.g. an informally-named reference ("Inu sp. 1 sensu Shibukawa et al., 2020.") extracts genus = "Inu", but GBIF's own backbone resolves it to the currently-accepted genus "Luciogobius", so "Luciogobius" is returned. This matters beyond cosmetics: TaxaAssign::join_priors() joins this function's genus/family output against a likelihood-side coarse-rank taxon_name (produced by TaxaMatch::convert_taxonomy_backbone(), which also prefers the current name over a synonym) via an EXACT STRING match. If the two functions disagreed on which form to report for the same genus, that join would silently fail and the observation would lose its coarse-rank species expansion entirely, falling back to the dark-diversity floor instead of real occurrence-based priors. genus is corrected to the backbone's resolved name whenever an API lookup finds one cleanly at genus rank, keeping this function consistent with convert_taxonomy_backbone(). Verified backbone-general: both NCBI and GBIF resolve the "Inu" case the same way.

### find_taxonomy_conflicts(input_df, rank_system = NULL)

Find Taxonomic Conflicts in a Taxonomy Data Frame

Detects higher-rank inconsistencies: cases where the same taxon name at one rank is assigned to different parent taxa at a coarser rank across rows.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame with taxonomy columns (e.g. family, genus, species). |
| rank_system | no | NULL | Character vector of rank column names, coarse to fine. If NULL (default), auto-detected via detect_ranks(). |

**Value:** A data frame of conflicts with columns: 'taxon_name' The taxon name that has conflicting higher-rank assignments. 'taxon_rank' The rank of the conflicting taxon (e.g. '"genus"'). 'parent_rank' The coarser rank where disagreement was found (e.g. '"family"'). 'parent_values' Semicolon-separated string of the distinct parent values found (e.g. '"Cottidae; Scorpaenidae"'). 'n_values' Number of distinct parent values. Returns an empty data frame (0 rows, same columns) when no conflicts are found.

#### Details

These conflicts arise when merging taxonomy from multiple sources (GBIF + NCBI + WoRMS) or when supplementing verified taxonomy with manual corrections. Adapted from the GITA pipeline's f_find_taxonomic_inconsistencies(), vectorised for performance.

### is_plausible_binomial(x)

Test Whether Strings Are Plausible Species Binomials

Returns TRUE for strings that are structurally plausible species binomials matching the '"Genus epithet"' pattern and not matching common placeholder patterns ('sp.', 'cf.', 'aff.', 'uncultured', 'environmental', 'metagenom').

| Param | Required | Default | Doc |
|---|---|---|---|
| x | yes |  | Character vector of taxon name strings. |

**Value:** Logical vector, same length as 'x'.

#### Details

Useful for filtering NCBI taxonomy results and occurrence records to described, named species only.

### list_cache_files(cache_dir, patterns, recursive = FALSE, force = FALSE)

List files in a directory matching cache-file patterns

Generic building block for a package's own '<pkg>_clear_cache()' helper: scans 'cache_dir' and returns every file whose basename matches any of 'patterns', with size and modification time. See 'TaxaFetch::taxafetch_clear_cache()'/ 'TaxaLikely::taxalikely_clear_cache()' for worked examples of a downstream package building on this.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | yes |  | Character. Directory to scan. |
| patterns | yes |  | Character vector of regular expressions matched against each file's basename (via grepl()); a file matching ANY pattern is included. |
| recursive | no | FALSE | Logical. Descend into subdirectories? Default FALSE. Pass TRUE for a store that keeps part of itself in a subdirectory -- TaxaLikely's per-accession fasta/ cache is one example; without it, files inside that subdirectory are invisible to taxalikely_clear_cache(). Patterns are still matched against the BASENAME, so a recursive scan needs a pattern that identifies the file, not its directory. |
| force | no | FALSE | Logical (default FALSE). Pass TRUE to scan a directory that holds files matching none of patterns anyway -- see containment check (2) above. Never needed for a directory that holds only recognized cache files. |

**Value:** A data frame with columns 'path', 'size_mb', 'mtime' (zero rows if 'cache_dir' has no matching files or does not exist).

#### Details

Three containment checks apply before anything is returned (all part of this shared engine, so every downstream <pkg>_clear_cache() inherits them): (1) cache_dir is refused outright if it resolves to the working directory, the user's home directory, or a filesystem root -- see .assert_cache_dir_is_dedicated(); (2) a directory holding any file that matches NONE of patterns is refused unless force = TRUE -- a real cache directory holds only cache files, so a mixed one is somebody's project, not a cache, even if some of its files happen to match; (3) under recursive = TRUE, a symlinked subdirectory (or file) that resolves outside cache_dir is never followed, so a scan cannot escape cache_dir via a symlink.

### list_models(provider = NULL)

List Current LLM Model Tier Assignments

Shows the model name that each tier ('fast', 'mid', 'top') resolves to for each provider whose API key is set. Also shows the source of the assignment: a session pin, a live API discovery, or the bundled fallback.

| Param | Required | Default | Doc |
|---|---|---|---|
| provider | no | NULL | Character vector. Provider name(s) to show. Default NULL shows all providers with an API key set in the environment. |

**Value:** A data frame (invisibly) with columns 'provider', 'tier', 'model', 'source'.

#### Details

Models are discovered lazily -- the first call for a provider triggers a live /models API query and caches the result for the session. Use refresh_models to force re-discovery.

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

#### Details

This function is vectorised over path and ranks via mapply(). To parse an entire column from verify_taxon_names() output use:

```
verified <- verify_taxon_names(stringr::word(species_names, 1))
families <- mapply(
  parse_classification_path,
  verified$classification_path,
  verified$classification_ranks,
  MoreArgs = list(target_rank = "family")
)
```

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

#### Details

Returns the combined raw response text from all chunks for passing to a response parser such as parse_hierarchical_habitat_response() (TaxaHabitat).

Prompt types in TaxaID: The term "prompt" has two distinct meanings in the ecosystem:

- llm_prompt S3 object: A structured multi-chunk prompt created by domain functions (e.g., build_habitat_prompt() in TaxaHabitat). Contains chunked prompts, metadata, and taxa lists. Used by prompt_api() and prompt_manual().

- Plain character string: A single text prompt passed directly to provider functions (call_api(), call_anthropic_api(), etc.) or to draft_methods_text() / draft_results_text().

prompt_api() requires the S3 object; the individual provider functions accept plain strings.

Provider selection: All provider-specific concerns (API keys, model names, token limits) belong inside the llm_fn function. Use a closure to fix non-default parameters for any provider:


```

# Specific provider and tier via call_api my_fn <- function(p, ...) call_api(p, provider = "gemini", tier = "fast")

# Anthropic with a non-default model my_fn <- function(p, ...) call_anthropic_api(p, model = "claude-haiku-4-5-20251001")

# Local Ollama model my_fn <- function(p, ...) call_ollama_api(p, model = "qwen2.5:14b")

raw_text <- prompt_api(prompt, llm_fn = my_fn) ```

### prompt_manual(prompt, out_dir = getwd(), prefix = "habitat")

Submit a Prompt Manually via Any LLM Interface

Writes prompt file(s) from an 'llm_prompt' object to disk and prints step-by-step instructions for manual submission to any LLM web interface or desktop app (Path 3). Pauses R execution until the user presses Enter, preventing the next script lines from running prematurely.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt | yes |  | An llm_prompt object (e.g. from build_habitat_prompt() (TaxaHabitat)). |
| out_dir | no | getwd() | Character. Directory to write prompt and response files. Default getwd(). Created if it does not exist. |
| prefix | no | "habitat" | Character. Filename prefix. Default "habitat". Files are named <prefix>_prompt_1.txt, <prefix>_prompt_2.txt, etc. |

**Value:** Invisibly returns a named list: prompt_files Character vector of written prompt file paths. response_files Character vector of expected response file paths. n_chunks Integer. Number of chunks. taxon_list Character vector. All taxa submitted.

#### Details

The function pauses R by calling readline() after printing instructions. This is intentional -- it prevents the next line of your script (typically read_llm_response()) from running before you have saved the response file(s).

### read_llm_response(files)

Read Saved LLM Response File(s)

Reads one or more plain-text LLM response files, strips duplicate CSV headers from chunks 2 onward, and returns a single concatenated string ready for a response parser.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Path(s) to response file(s). Files are read and concatenated in order. For multi-chunk submissions, supply all chunk files in the same order they were submitted. |

**Value:** A length-1 character string.

#### Details

Missing files generate a warning (not an error) so that partial results can still be parsed. If taxon_name is absent from the combined text, a warning is also emitted.

### refresh_models(providers = NULL)

Refresh LLM Model Discovery from Provider APIs

Queries each provider's '/models' endpoint to find the latest available models, applies tier patterns to assign 'fast'/'mid'/'top' tiers, and saves the results to the local persistent cache. Only providers with an API key set in the environment are queried.

| Param | Required | Default | Doc |
|---|---|---|---|
| providers | no | NULL | Character vector. Provider names to refresh. Default NULL refreshes all providers with keys set. |

**Value:** A data frame of updated tier assignments (invisibly), as from 'list_models'.

#### Details

Call this function when a model name becomes stale (e.g., a 404 deprecated error) or after adding a new API key.

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

#### Details

Registered providers are session-only and do not persist to disk. Add the call to ~/.Rprofile or the top of your analysis script for automatic re-registration.

### rename_cols(input_df, col_map = NULL, strict = FALSE)

Rename Data Frame Columns to a Target Convention

Renames columns in a data frame using either a user-supplied explicit map or a set of built-in case-insensitive regex patterns that cover common alternatives to DarwinCore column names. Intended as the first step when aligning supplemental occurrence data to a shared column naming convention before combining sources with 'stack_occurrences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | A data frame whose columns are to be renamed. |
| col_map | no | NULL | Named character vector or NULL. When supplied, each name is an existing column name in input_df and each value is the desired new name. Both must be quoted strings: col_map = c("Latitude" = "decimalLatitude", "Longitude" = "decimalLongitude", "SurveyDate" = "eventDate") When col_map is supplied it replaces the default pattern matching entirely -- only the mappings you specify are applied. When NULL (default), the built-in regex patterns are used instead (see Details). |
| strict | no | FALSE | Logical. Controls behaviour when a col_map key is not found in input_df. FALSE (default): warns about unmatched keys and renames whatever it can. Suitable when rename_cols() is applied to frames that may only contain some of the target columns. TRUE: stops with an error if any col_map key is absent from input_df. Use in scripts where all mappings must succeed. Has no effect when col_map = NULL (default patterns always skip non-matching columns silently). |

**Value:** The input data frame with columns renamed as specified. Column types, row names, and all other attributes are preserved. Columns not mentioned in 'col_map' (or not matched by the default patterns) are left unchanged.

#### Details

Default pattern matching (when col_map = NULL): The following case-insensitive regex patterns are applied. A column is renamed only when its name matches exactly one pattern; ambiguous matches (multiple columns matching the same pattern) are skipped with a warning.

- lat, latitude -> decimalLatitude

- lon, long, longitude -> decimalLongitude

- date, SurveyDate, CollectionDate, EventDate, DateCollected -> eventDate

- site, location, locality -> verbatimLocality

Matching is case-insensitive so Lat, LAT, and lat all match. If the target column already exists in input_df (e.g. input_df already has decimalLatitude), that pattern is skipped.

User col_map replaces defaults: When col_map is supplied, none of the default patterns are applied.

Quoted strings required: Both names and values in a user-supplied col_map must be quoted. Unquoted bare names cause an "object not found" error before the function is called.

Scientific name columns: No default pattern maps to scientificName or taxon_name. Column names such as Species are ambiguous (they may hold the epithet only, not the full binomial) and must be mapped explicitly via col_map after confirming column content.

#### The col_map pattern across TaxaID

The col_map concept is used consistently across the TaxaID ecosystem wherever column names need to be reconciled:

- TaxaTools: rename_cols() -- general-purpose column rename with DarwinCore defaults.

- TaxaMatch: standardize_match_data() -- map BLAST/DADA2 output column names to the canonical match object format.

- TaxaFetch: stack_occurrences() -- align column names across occurrence data sources before row-binding.

In all cases, col_map is a named character vector where names are existing column names and values are desired target names.

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

#### Containment

cache_dir is refused outright (before anything is deleted, even under dry_run = FALSE) if it resolves to the working directory, the user's home directory, or a filesystem root -- the same check list_cache_files() applies, repeated here so a caller that builds inv some other way (not via list_cache_files()) still gets it. inv itself is used as-is and is not re-scanned or re-filtered against cache_dir -- a caller is trusted to have built it FROM cache_dir.

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

#### Details

For vector input (multiple marker names), collects all matched ranges and returns c(min(mins), max(maxes)) so the query covers all supplied terms. User-supplied min_len / max_len override the resolved bounds.

### resolve_barcode_marker(barcode_term)

Resolve a Primer-Variant Barcode Term to the Marker It Amplifies

A registered primer-variant name (see barcode_primer_defaults) - '"COI-Folmer"', '"16S-Palumbi"', '"rbcLa"' - is the correct term for resolving primers and amplicon lengths, but it is *not* a term any sequence database indexes: no GenBank record is tagged "Folmer". A search query built from the variant name matches nothing, and because "nothing found" is a legitimate outcome of a search, that failure is silent - it looks like the taxon has no barcode rather than like a bad query.

| Param | Required | Default | Doc |
|---|---|---|---|
| barcode_term | yes |  | Character vector of barcode/marker/primer-variant names. |

**Value:** Character vector the same length as 'barcode_term': the base marker name for a recognised primer variant, otherwise the input unchanged.

#### Details

This maps such a term to the marker it amplifies, so a search can be built from the marker while primer/length resolution keeps using the variant. Any term that is not a recognised variant is returned unchanged, so a custom or unregistered term still searches as itself.

MiFish terms are deliberately not remapped: unlike the others, real records are annotated with the MiFish primer name, so the variant is genuinely searchable and callers already OR it together with 12S.

### resolve_barcode_primers(barcode_term)

Resolve Primer Sequences from a Barcode/Primer-Set Term

Looks up 'barcode_term' in barcode_primer_defaults. Unlike 'resolve_barcode_lengths()', matching requires the _specific_ primer variant (e.g. '"MiFishU"', not bare '"MiFish"') because different variants of what is loosely called "the same marker" can have genuinely different primer sequences - silently picking one would be a real correctness risk, not a convenience shortcut. An ambiguous or unlisted term errors with guidance rather than guessing.

| Param | Required | Default | Doc |
|---|---|---|---|
| barcode_term | yes |  | Character scalar naming a specific primer set (e.g. "MiFishU", "mifish-e"). Matching is case-insensitive and ignores -/_/space separators. |

**Value:** A list with 'fwd', 'rev' (character, 5'-3') and 'amplicon_range' (integer 'c(min_bp, max_bp)').

### resolve_ncbi_taxid(name, rank = NULL, lineage_terms = NULL)

Resolve a taxon name to one disambiguated NCBI taxonomy id

A taxon name is not a key - NCBI can hold several nodes with the same name in unrelated lineages (real confirmed cases include a genus of red algae named "Vertebrata" beside the vertebrate clade of the same name, and a genus of moths named "Lobophora" beside a genus of brown algae of the same name), and a name-based sequence search silently resolves to whichever node the service prefers. This function disambiguates by resolving to a taxonomy id first, using the caller's OWN declared rank and/or higher-rank lineage as discriminators, so a caller can then query by 'txid<id>[ORGN]' instead ...

| Param | Required | Default | Doc |
|---|---|---|---|
| name | yes |  | Character scalar. The taxon name to resolve. |
| rank | no | NULL | Character scalar or NULL (default). The caller's own declared rank for name (e.g. "genus"), used as the first discriminator. Case-insensitive. |
| lineage_terms | no | NULL | Character vector or NULL (default). The caller's own known higher-rank names for name (e.g. c("Rhodomelaceae", "Ceramiales", "Florideophyceae", "Rhodophyta")), used as the second discriminator when rank alone cannot decide. |

**Value:** A list: taxid Character scalar, the resolved NCBI taxonomy id, or 'NA_character_' if not found or ambiguous. status One of '"unique"' (only one node has this name), '"resolved_by_rank"', '"resolved_by_lineage"', '"ambiguous"' (more than one candidate survived both discriminators), or '"not_found"'. candidates A data frame of every NCBI node sharing this name ('taxid', 'rank', 'division', 'genbankdivision', 'scientificname'), for logging/inspection regardless of status. Zero rows when 'status == "not_found"'.

#### Details

Two discriminators are tried, in order, whenever a name resolves to more than one node:

- Rank. If rank is supplied, candidates whose own NCBI rank does not match are dropped. This alone resolves many real cases (e.g. a genus-rank alga vs. a clade-rank "Vertebrata"), but is NOT sufficient alone -- two candidates can share the same rank (e.g. two genus-rank "Lobophora", one a moth, one a brown alga).

- Lineage containment. If more than one candidate survives the rank filter (or rank was not supplied at all), each surviving candidate's own full NCBI lineage is fetched and tested for ANY overlap (case-insensitive) with lineage_terms -- the caller's own known higher-rank names for this taxon (e.g. its phylum, class, order, family). A candidate with zero overlap is dropped.

A name resolving to exactly one surviving candidate at any stage is returned as the answer; a name resolving to zero or more than one after both discriminators is reported "ambiguous" rather than guessed.

### scientific_to_common(scientific_names, backbone_id = 11L, location = NULL, use_llm = FALSE, llm_fn = getOption("TaxaID.llm_fn"), cache_dir = NULL, verbose = TRUE, ...)

Convert Scientific Names to Common Names

Looks up English common names for a character vector of scientific names. By default queries the GBIF vernacular names database ('backbone_id = 11') or ITIS ('backbone_id = 3'); a backbone miss is left as 'NA' unless 'use_llm = TRUE' is explicitly requested (the default is 'FALSE', not 'TRUE'). Set 'backbone_id = NULL' to use the LLM for all names without a backbone query.

| Param | Required | Default | Doc |
|---|---|---|---|
| scientific_names | yes |  | Character vector of scientific names to look up. |
| backbone_id | no | 11L | Integer or NULL. Backbone for structured lookup: 11 = GBIF (default, uses rgbif), 3 = ITIS (uses taxize). Other values trigger a warning and fall through to the LLM. NULL skips backbone lookup entirely. |
| location | no | NULL | Character string providing geographic context for the LLM (e.g., "Southern California Bight", "Pacific Northwest, USA"). Biases the LLM toward regionally appropriate common names. Has no effect on backbone-sourced results. Default NULL. |
| use_llm | no | FALSE | Logical. If TRUE, taxa with no backbone result are sent to the LLM in batches of 20 names (one progress line per batch when verbose). Default FALSE: returns NA for unresolved taxa without an LLM call. A name the LLM omits from its batch response is NOT cached -- it is re-asked on a later call rather than silently treated as a confirmed "no common name" answer. |
| llm_fn | no | getOption("TaxaID.llm_fn") | Function with signature function(prompt, ...) -> character(1). Required when use_llm = TRUE or backbone_id is unsupported / NULL. Default getOption("TaxaID.llm_fn"). |
| cache_dir | no | NULL | Character or NULL (default, no cache). A directory holding one small .rds per looked-up name, keyed on the name (case/whitespace-insensitive), backbone_id and location. A name found there is served without any backbone or LLM call; a name resolved this call is written back. A name the LLM was asked about and answered "no common name" IS cached (that is its answer); a name from a batch the LLM answered unparseably is NOT (it will be re-asked), and neither is a backbone miss on a use_llm = FALSE call (a later use_llm = TRUE call must still be able to ask). Manage it with taxatools_clear_cache. Without a cache, a large name list means one silent LLM call per batch on every run, repeated on every re-run. |
| verbose | no | TRUE | Logical (default TRUE). Print a one-line summary (cache / backbone / LLM counts) and one line per LLM batch. |
| ... | yes |  | Additional arguments passed to llm_fn. |

**Value:** A data frame with one row per element of 'scientific_names': 'scientific_name' Input scientific name (character). 'common_name' Primary English common name, or 'NA'. 'common_name_alternatives' Semicolon-delimited additional English common names, or 'NA'. 'source' One of '"gbif"', '"itis"', '"llm"', or '"none"'. 'backbone_id' Integer backbone ID used, or 'NA' for LLM or no-result rows.

#### Details

Backbone sources return structured, curated common names and are preferred when available. GBIF filters to vernacular names with language = "eng"; ITIS filters to language = "English". The first name returned becomes common_name; remaining names become common_name_alternatives (semicolon-delimited).

When backbone_id is not 3 or 11 (or is NULL), only the LLM is used. A warning is issued for unsupported backbone IDs. When a backbone package is required but not installed, an error is thrown with installation instructions.

The location parameter is passed to the LLM and biases name selection toward regionally appropriate common names (e.g., Pacific vs. Atlantic range variants, locally used vernacular names). It has no effect on backbone-sourced results. To apply geographic context to all names, set backbone_id = NULL so the LLM handles the full lookup.

### set_model(provider, tier, model)

Pin a Specific Model Version for Reproducibility

Overrides dynamic tier resolution for the current R session. Use at the top of an analysis script to lock the exact model version, ensuring results can be reproduced regardless of what the provider currently returns as 'latest'.

| Param | Required | Default | Doc |
|---|---|---|---|
| provider | yes |  | Character. Provider name: "anthropic", "gemini", "openai", or "azure_openai". |
| tier | yes |  | Character. Tier to pin: "fast", "mid", or "top". |
| model | yes |  | Character. Exact model identifier to use, or NULL to remove an existing pin. |

**Value:** The model string invisibly.

#### Details

Pins are session-only and do not affect the persistent cache. To unpin, restart R or call set_model(provider, tier, NULL).

### taxaid_build_manifest(packages = NULL)

Record Which TaxaID Code a Run Is Using

Captures, for each TaxaID package, its version, 'Built' timestamp and a hash of its installed code. Save it beside a run's outputs and every result becomes traceable to the exact build that produced it.

| Param | Required | Default | Doc |
|---|---|---|---|
| packages | no | NULL | Character vector of package names. Defaults to the nine TaxaID packages. |

**Value:** A data frame with columns 'package', 'version', 'built', 'code_hash', 'installed'. Packages that are NOT installed appear with 'installed = FALSE' rather than being dropped - absence has to be representable for 'check_taxaid_manifest()' to report it.

### taxaid_cache_report(extra_dirs = NULL, warn_gb = 1)

Report every TaxaID cache on this machine

Each package has its own '<pkg>_clear_cache()' function, but none of them shows the whole picture - a handful of large GBIF zip files can dominate total cache size while every other cache file combined stays small, and that is invisible without an ecosystem-level view. This function is that view: it reports, and never deletes.

| Param | Required | Default | Doc |
|---|---|---|---|
| extra_dirs | no | NULL | Character vector of additional cache directories to include -- typically the project-local ones a workflow passes as cache_dir. Non-existent paths are reported as missing rather than dropped, so a typo is visible. |
| warn_gb | no | 1 | Numeric. Directories at or above this size are flagged in the printed output. Default 1. Set NULL to disable flagging. |

**Value:** Invisibly, a data frame with one row per directory: 'cache', 'path', 'exists', 'n_files', 'size_mb', 'oldest', 'newest'. 'size_mb' is APPARENT size (sum of file bytes). A cache of many tiny files occupies substantially more than that on disk, because each file takes at least one filesystem block - TaxaLikely's per-taxon and per-accession stores are thousands of ~1 KB files, so their real footprint is roughly 'n_files' x block size. Read 'n_files' alongside 'size_mb'; the printed output flags stores where the two diverge.

#### Details

Caches default to tools::R_user_dir("<pkg>", "cache"), a hidden per-user directory outside the project, so the sizes here are usually invisible from the analysis they belong to. Project-local cache directories (the file.path(OUT_DIR, ...) convention the workflows use) are not discoverable automatically -- pass them via extra_dirs.

Counts files recursively, so nested stores such as TaxaLikely's fasta/ subdirectory are included.

#### Deliberately not a clear function

Two of these caches do not share one shape. The file-per-key caches (TaxaFetch, TaxaFlag, TaxaHabitat, TaxaLikely) are served by report_and_clear_cache(). TaxaMatch's is row-level and TTL'd -- a few files each holding many entries with their own lifetimes -- so deleting at file granularity would discard live rows. That is why TaxaMatch has no clear_cache() function, and why this one only reports. See list_cache_files()'s note on cache shapes.

### taxatools_clear_cache(cache_dir, older_than_days = NULL, dry_run = FALSE, force = FALSE)

Report and clear the TaxaTools on-disk caches

Covers the package's three file-per-key caches: 'scientific_to_common(cache_dir = )' (one '.rds' per looked-up name), 'fetch_worms_attributes(cache_dir = )' (one '.rds' per looked-up taxon) and 'verify_taxon_names(cache_dir = )' (one '.rds' per answered name). This helper reports what the directory holds and deletes it (optionally only files older than 'older_than_days'), via the shared 'report_and_clear_cache' engine - the same shape as 'TaxaFetch::taxafetch_clear_cache()' and 'TaxaFlag::taxaflag_clear_cache()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | yes |  | Character. The directory passed to scientific_to_common(cache_dir = ) or fetch_worms_attributes(cache_dir = ). |
| older_than_days | no | NULL | Numeric or NULL. Only files older than this many days are targeted; NULL (default) targets every file. |
| dry_run | no | FALSE | Logical. If TRUE, reports without deleting. |
| force | no | FALSE | Logical (default FALSE). cache_dir is refused if it holds any file matching neither cache pattern (a real cache directory holds only cache files) or if it resolves to the working directory, the user's home directory, or a filesystem root (that last refusal is never overridable by force) -- see list_cache_files's own @section on this. Pass TRUE only for the first kind of refusal, and only once you have confirmed the non-matching file(s) named in the error are not real data. |

**Value:** Invisibly, the data frame of targeted files (see 'list_cache_files').

#### Details

Note that WoRMS attributes carry no TTL because they are curated and do not drift between runs; clearing them is how you pick up a WoRMS revision.

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

#### Details

Column mapping applied (TaxaID \to FAIRe):

- observation_id \to seq_id

- taxon_name \to scientificName

- taxon_name_rank \to taxonRank

- score \to percent_match

- coverage \to percent_query_cover

- testid \to assay_name

- accession \to accession_id

- kingdom, phylum, class, order, family, genus, species -- unchanged (already match FAIRe / Darwin Core names)

Columns constructed:

- verbatimIdentification -- semicolon-delimited taxonomy string (FAIRe convention) built from whichever of kingdom through species are present and non-NA in each row.

- specificEpithet -- species epithet extracted from the species column (second word of the binomial), when species is present.

- checkls_ver -- FAIRe checklist version (Mandatory field).

Scope: The FAIRe checklist covers the full eDNA workflow including sample collection, extraction, PCR, and sequencing. TaxaID outputs map only to the taxaRaw and taxaFinal classes (bioinformatics taxonomic assignment tables). Sample-level metadata (samp_name, eventDate, decimalLatitude, etc.) must be supplied by the user from field records and joined to this output before submission.

### token_usage(by = c("call", "function", "provider", "session"), cost_per_1k_input = NULL, cost_per_1k_output = NULL)

Summarise LLM Token Usage for the Current Session

Returns a data frame of token usage records accumulated since the last call to 'reset_token_usage' (or since 'library(TaxaTools)'). Every call to 'call_api' appends one record automatically; no changes are needed in downstream package functions.

| Param | Required | Default | Doc |
|---|---|---|---|
| by | no | c("call", "function", "provider", "session") | Character. How to aggregate: "call": One row per individual API call (default). Includes timestamp, caller function, provider, model, and token counts. "function": Totals per caller function. "provider": Totals per provider. "session": Single-row grand total for the session. |
| cost_per_1k_input | no | NULL | Numeric or NULL. If supplied, adds a cost_usd column estimated as (input * cost_per_1k_input + output * cost_per_1k_output) / 1000. Default NULL (no cost column). |
| cost_per_1k_output | no | NULL | Numeric or NULL. Output cost rate. Used only when cost_per_1k_input is non-NULL. Default NULL (same rate as input). |

**Value:** A data frame. Columns depend on 'by': '"call"' 'timestamp', 'caller', 'provider', 'model', 'input', 'output', 'total' '"function"' 'caller', 'n_calls', 'input', 'output', 'total' '"provider"' 'provider', 'n_calls', 'input', 'output', 'total' '"session"' 'n_calls', 'input', 'output', 'total' Returns an empty data frame with a message if no calls have been recorded.

### verify_taxon_names(name_list, backbone_id, batch_size = 500, timeout_sec = 30, fallback_backbone_id = 11L, decisions = NULL, cache_dir = NULL, cache_ttl_days = 365, input_rank = NULL, lineage = NULL)

Verify Taxon Names Against a Taxonomic Backbone

Checks a vector of taxon names against a target taxonomic backbone using the Global Names Verifier API (v1). Returns the best match for each name along with classification path, ranks, a match score, and a flag indicating whether verification succeeded.

| Param | Required | Default | Doc |
|---|---|---|---|
| name_list | yes |  | A character vector of taxon names to verify. Duplicates are removed automatically. |
| backbone_id | yes |  | Integer. The numeric ID of the target taxonomic backbone. Common options: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS, 11 = GBIF. See https://verifier.globalnames.org/ for the full list. |
| batch_size | no | 500 | Integer. Maximum number of names per API request. The Global Names Verifier API supports up to 1000 names per batch. Default is 500 to stay safely within limits. |
| timeout_sec | no | 30 | Integer. Seconds to wait before the API request times out. Default is 30. |
| fallback_backbone_id | no | 11L | Integer. Only used when backbone_id = 4 (NCBI). NCBI's direct lookup is an exact string search with no typo tolerance -- a single misspelled letter returns zero hits even via its own synonym fallback. When that happens, this backbone's Global Names Verifier API is queried instead purely to suggest a corrected spelling, which is then re-resolved through NCBI itself (the correction is never accepted from this backbone directly, so NCBI's own classification -- the reason the direct bypass exists at all -- is preserved). Default 11 (GBIF). Must not be 4. |
| decisions | no | NULL | Only used when backbone_id = 4 (NCBI); a supplied value is ignored, with a warning, for any other backbone. A name is not a key -- NCBI can hold several nodes sharing one name in unrelated lineages (a genus of red algae named "Vertebrata" beside the vertebrate clade of the same name; see resolve_ncbi_taxid), and this direct bypass's own batched search used to pick whichever candidate its summary happened to process last, silently. Such a name is now reported as an unresolved AMBIGUITY, never guessed -- decisions is how a caller states which candidate is meant. NULL (default): no prior decisions. A data frame with name/taxid columns: use these decisions directly (a row with taxid = NA is an explicit skip -- that name resolves to NA, not "not yet decided"). A character scalar: the path to an .rds file holding such a data frame (read if it exists; new decisions made this call -- interactively, see below -- are merged into it, a newer decision for a name replacing an older one). A name that comes back ambiguous and has no covering decision (in decisions or, for a path, already saved in that file) is handled by session type, never by a silent default: in an interactive session, one prompt covers every such name in this call (never a dialogue per name), tabulating each candidate's rank, division, and a short lineage string; in a non-interactive session (the ordinary Rscript workflow case), the call stops, printing that same table plus a ready-to-paste decisions = data.frame(...) skeleton. No file is ever written unless decisions itself named one. That stop applies only when decisions was supplied and does not cover the name: a non-interactive call with decisions = NULL (the shape of a batch issued from inside another function, which has no way to pass a decision) instead reports the still-ambiguous name alone as verified = FALSE -- never cached, asked again next call, with the candidate table in a warning -- and the rest of the batch proceeds. |
| cache_dir | no | NULL | Character or NULL (default). A directory for a per-name on-disk cache, so a re-run on the same names reproduces instead of depending on whether the service answered this time. Only names the service actually answered are cached -- matched or genuinely unmatched (verified = TRUE); a name whose lookup FAILED (verified = FALSE) is never written and is asked again next call, because a cached non-answer would be served as an answer indefinitely. Every entry written carries an answered marker; an entry from before the marker existed is served only if it holds a matched name (a failed lookup never produces one) and is otherwise asked once more and rewritten. The key is the name plus everything that can change what it resolves to: backbone_id, fallback_backbone_id, decisions (by content, including a decisions file's contents) and, on the NCBI path when one is given, the name's rank. batch_size and timeout_sec are not in the key; they cannot change a correct answer. Managed by taxatools_clear_cache. NULL keeps the uncached behaviour exactly. |
| cache_ttl_days | no | 365 | Numeric (default 365). A cached answer older than this is asked again, so backbone updates (renames, new synonymy) eventually reach a long-lived cache. Inf never expires. |
| input_rank | no | NULL | Character vector or NULL (default). One rank per element of name_list ("genus", "species", ...; NA where unknown): the rank the CALLER means each name at. Only used by the NCBI path (backbone_id = 4) and only for a name that resolves to more than one NCBI node: when exactly one candidate carries the given rank, that node is taken, with no further request and before decisions is consulted. "Etheostoma" is both a genus and a subgenus; a consensus table knows which it means. On the Global Names path it does not change the query (one best match is returned) but it decides, with lineage, whether that match can be gated: a match at another rank is gated on its lineage, a match at the asked rank only on a kingdom difference (see lineage). On the NCBI path a rank that is given enters the cache key (see cache_dir); elsewhere the key is unchanged. |
| lineage | no | NULL | Character vector or NULL (default). One lineage context per element of name_list (NA = none): a pipe-delimited string of ancestor names the caller already knows for that name, e.g. "Chordata" or "Metazoa\|Chordata\|Actinopteri". Used twice. On the NCBI path (backbone_id = 4) a homonym is resolved, after input_rank and before decisions, to the one candidate whose own lineage contains any of the context's names (the candidates' lineages are already fetched for the ambiguity report, so this adds no request); zero or several containing candidates leave it ambiguous. Second, a returned classification that contradicts the context -- both carry comparable names (kingdoms are ignored, see check_lineage_agreement()) and share none -- is reported as unverified, never accepted, but only where a CHOICE between taxa existed: on the NCBI path a name that had several candidates and was settled by input_rank or decisions; on the Global Names path (one best match, no candidate set) a match whose rank differs from input_rank, or any match when no rank was given; a match AT the asked rank is gated only when the context names a kingdom (Animalia or Metazoa, Plantae or Viridiplantae, Fungi, Chromista, Protozoa, Bacteria, Archaea) and the returned path's kingdom differs, since a same-rank homonym such as Ulvaria (a fish genus and an alga genus) crosses kingdoms while a reclassification never does. A unique node, or a same-rank match within one kingdom, is accepted however the backbones word its lineage: NCBI carries no phylum rank for many protist lineages, and GBIF and NCBI name the same clades differently, which is reclassification, not a homonym. A name is not a key; this is the caller's way of saying which one it means. Part of the cache key when given. |

**Value:** A tibble with one row per input name and the following columns: user_supplied_name The original name as supplied. matched_name The best-matched name at whatever rank the backbone actually resolved it to (authorship strings stripped; a genus-only match returns a bare genus, a subspecies-level match returns the full trinomial), or 'NA' if no match was found. When the backbone itself flags the match as a taxonomic synonym ('is_synonym = TRUE'), this is the backbone's OWN currently-accepted name, not the (possibly outdated) synonym form that was actually queried - see 'is_synonym' below. Sourced from the Global Names Verifier API's own canonical-name fields, not a local regex, so it is not vulnerable to truncating a trinomial to a binomial the way a naive genus-plus-one-epithet parse would. matched_rank Character. The taxonomic rank 'matched_name' itself was actually resolved at (e.g. '"species"', '"genus"', '"subspecies"') - the last rank present in 'classification_ranks'. Use this, not an assumption carried over from whatever rank the input name was expected to be, to decide how to use 'matched_name' downstream: a query submitted as a species binomial can genuinely resolve only to genus (e.g. an informally-named taxon with no species-level backbone entry), and treating the returned name as still species-level in that case silently corrupts a genus-only name into a fabricated pseudo-binomial. 'NA' when no match was found. is_synonym Logical. 'TRUE' when the backbone's own best match for this name is a taxonomic synonym of a currently-accepted name (in which case 'matched_name' already reports the accepted form, not the synonym). 'NA' when unknown (no match, an API failure, or - for 'backbone_id = 4' specifically - always, since NCBI's direct lookup path does not expose synonym relationships the way the Global Names Verifier path does). Synonymy is a property of the SPECIFIC backbone queried, not a universal fact - the same name can be a synonym under one backbone's own taxonomic opinion and not another's (confirmed directly: GBIF/Catalogue of Life/WoRMS all flag '"Inu"' Snyder 1909 as a synonym of '"Luciogobius"' Gill 1859, while NCBI's own taxonomy does not consider it one at all). This column always reflects whichever single 'backbone_id' was actually queried. classification_path Pipe-delimited classification path from the backbone (e.g., '"Animalia|Chordata|..."'). Already reflects the currently-accepted lineage even when the query matched a synonym. classification_ranks Pipe-delimited rank labels corresponding to 'classification_path'. score Backbone match confidence score between 0 and 1. Higher is better. This measures name-matching quality against the backbone and is unrelated to the sequence match scores used elsewhere in the TaxaID ecosystem (e.g., percent identity from BLAST). verified Logical. 'TRUE' if the lookup ran and the API answered, 'FALSE' if the API failed and fallback values were used - or, when 'lineage' was given, if the API answered and the answer contradicted the caller's lineage (see 'lineage'). The second case is deterministic: the same name with the same context is rejected every time, so retrying it is pointless; the message that names each rejected name tells the two cases apart. It does not say whether the name was found: a name the backbone does not hold returns 'verified = TRUE' with 'matched_name = NA'. Always check rows where 'verified = FALSE'. matched Logical. 'TRUE' only when the lookup ran and returned a name ('verified & !is.na(matched_name)'). Filter on this, not on 'verified', to keep resolved names. fuzzy_corrected Logical. Only present when 'backbone_id = 4'. 'TRUE' if this name was not found by NCBI's own exact search and was instead matched after a fuzzy-spelling correction suggested by 'fallback_backbone_id' (see that parameter). Always review these rows before trusting them - a fuzzy match confirms a plausible correction, not a certain one.

#### Details

Because this function queries the internet, it can be slow for large name lists. It is recommended to run it once on a deduplicated list, save the result, and load that saved file in downstream scripts rather than calling this function repeatedly.

#### Synonym resolution and rank correctness (backbone-general, not GBIF-specific)

Verified directly against the live API across five backbones (Catalogue of Life, ITIS, NCBI, WoRMS, GBIF) with the same query: matched_rank (derived from classificationRanks) and isSynonym/currentName (used to prefer the accepted name over a synonym) are fields the Global Names Verifier API itself normalises identically across every backbone it aggregates -- nothing here is GBIF-specific code. What genuinely varies by backbone is the underlying taxonomic opinion (whether a given name counts as a synonym at all), not the mechanism for reading it. Because dataSources scopes every call to exactly one backbone, this always reports that one backbone's own answer -- it never blends or overrides one backbone's judgment with another's. backbone_id = 4 (NCBI) does not go through this API path at all (see .verify_via_ncbi()) and so never gets synonym resolution, but its own matched_rank is populated identically from its own classification lineage.

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
always agree: a name can be a live species in one and a retired synonym
in another (`is_synonym`/`matched_rank` will differ), which is exactly
why downstream packages let the caller choose rather than hardcoding
one:

| `backbone_id` | Backbone                                       |
|---------------|------------------------------------------------|
| 1             | Catalogue of Life                              |
| 3             | ITIS (Integrated Taxonomic Information System) |
| 4             | NCBI                                           |
| 9             | WoRMS (World Register of Marine Species)       |
| 11            | GBIF                                           |

``` r
# Same query, five backbones -- compare matched_name/is_synonym across them
backbones <- c(col = 1, itis = 3, ncbi = 4, worms = 9, gbif = 11)

lapply(backbones, function(id) {
  verify_taxon_names("Urobatis halleri", backbone_id = id)[
    , c("matched_name", "matched_rank", "is_synonym")
  ]
})
```

A mismatch here isn't a bug in `verify_taxon_names()`, it's telling you
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

