# CONTEXT: TaxaFetch

**Fetch and Prepare Taxonomic Occurrence Data**

Provides tools for acquiring, combining, and preparing taxonomic occurrence data from multiple sources including GBIF and DataONE. The user specifies a spatial area and taxonomic group; TaxaFetch retrieves occurrence records and aligns column naming to DarwinCore conventions. Habitat assignment and spatial quality control are handled by TaxaHabitat. Output is a data frame of taxonomic occurrences at various locations and times. These data feed into TaxaHabitat and then TaxaExpect, which generates spatially explicit predictions of relative occurrence across taxa. Part of the TaxaID ecosystem.

Version 1.0.0. 32 exported function(s).

## Functions

### build_geo_prompt(catalog, bbox, scope_lookup = NULL, chunk_size = 80L, verbose = TRUE)

Build a Geographic Screening Prompt for DataONE Datasets

Takes the full PASTA catalog (from 'harvest_dataone_catalog') and a target bounding box, optionally applies a user-supplied scope shortcut to pre-accept or pre-reject whole dataset scopes without an LLM call, deduplicates 'geographicdescription' values, and builds one or more LLM prompt strings asking whether each description falls within the bbox.

| Param | Required | Default | Doc |
|---|---|---|---|
| catalog | yes |  | A tibble from harvest_dataone_catalog. |
| bbox | yes |  | Numeric vector of length 4: c(west, east, south, north) in decimal degrees. Western longitudes should be negative. |
| scope_lookup | no | NULL | A data.frame with columns scope, west, east, south, north, and optionally label. Each row defines a dataset scope prefix (e.g. "knb-lter-sbc") and its bounding box. Packages whose scope starts with a listed prefix are pre-accepted (bbox overlaps) or pre-rejected (no overlap) without an LLM call. Default NULL sends all packages to the LLM. Use this to save tokens when you know which scopes are relevant. Example: scope_lookup = data.frame( scope = c("knb-lter-fce", "knb-lter-gce"), west = c(-81.2, -82.0), east = c(-80.4, -80.0), south = c(25.1, 30.5), north = c(25.8, 32.5), label = c("FCE LTER", "GCE LTER") ) |
| chunk_size | no | 80L | Integer. Maximum descriptions per prompt chunk. Default 80L. |
| verbose | no | TRUE | Logical. Report shortcut and dedup statistics. Default TRUE. |

**Value:** An object of classes 'c("geo_prompt", "llm_prompt")', a named list with elements: prompts List of prompt strings, one per chunk. chunks List of character vectors of descriptions, one per chunk. n_chunks Integer. n_items Integer. Number of unique descriptions sent to the LLM. descriptions Character vector. All unique descriptions submitted (in order matching the LLM index column). desc_to_ids Named list. Keys are descriptions, values are character vectors of dataset IDs that share that description. shortcut_accepted Character vector of dataset IDs pre-accepted via scope shortcut (bbox overlap confirmed without LLM). shortcut_rejected Character vector of dataset IDs pre-rejected via scope shortcut (bbox overlap impossible without LLM). catalog The full input catalog, for joining results back. bbox The input bbox.

#### Details

Returns a geo_prompt S3 object (also inheriting llm_prompt) that can be passed directly to prompt_api or prompt_manual.

Scope shortcut: When scope_lookup is supplied, packages whose scope column starts with a listed prefix are pre-decided by comparing the scope's known bounding box against the query bbox. This avoids LLM calls for scopes you already know are in or out of range. The shortcut is entirely user-controlled -- no geographic knowledge is hardcoded in the package.

Deduplication: Many datasets share identical geographicdescription values. Deduplication means the LLM sees each unique description exactly once; parse_geo_screening_response then fans the result back to all datasets sharing that description.

NA descriptions: Datasets with NA or blank geographicdescription are excluded from LLM screening and recorded in $shortcut_rejected.

### build_pdf_extract_prompt(pdf_structure, single_site_coords = NULL, dpi = 150L, chunk_pages = FALSE, verbose = TRUE)

Build a Stage 3 extraction prompt from a characterised PDF

Uses the five-axis classification in 'pdf_structure' to configure an extraction prompt that instructs the LLM to produce a Darwin Core CSV table of occurrence records from the targeted PDF page images.

| Param | Required | Default | Doc |
|---|---|---|---|
| pdf_structure | yes |  | A pdf_structure object from screen_pdf_structure(). |
| single_site_coords | no | NULL | Optional named list with elements lat and lon (numeric). Required when pdf_structure$single_site_rule == TRUE and the coordinates are not encoded in the structure object. Ignored otherwise. |
| dpi | no | 150L | Integer. Resolution for page image rendering. Default 150L. Reduce to 100L if the page count is very large and HTTP 429 errors occur. Values above 200 are not recommended for large documents. |
| chunk_pages | no | FALSE | Logical. When TRUE and the number of send pages exceeds 25, split the pages into chunks of at most 25 and return one prompt string per chunk in $prompts. Set $n_chunks > 1 in the returned object. Default FALSE. |
| verbose | no | TRUE | Logical. Print page-count and chunking information. Default TRUE. |

**Value:** An S3 object of class 'c("pdf_extract_prompt", "llm_prompt")' with elements: • '$prompts' - character vector of prompt strings (length 1 normally; '>1' when 'chunk_pages = TRUE' and 'n_send > 25') • '$page_chunks' - list of integer vectors, one per prompt, giving the page numbers for each chunk • '$n_chunks' - integer; number of chunks • '$n_send' - integer; total pages flagged for sending • '$dpi' - integer; dpi stored for use by caller • '$pdf_structure' - the input 'pdf_structure' object • '$single_site_coords' - list(lat, lon) or 'NULL' • '$abbreviation_inventory' - named character vector Returns 'NULL' invisibly (with a message) when 'observation_type' is '"analytical_modelling"' or '"experimental_lab"'.

### build_taxon_screen_prompt(catalog, taxon_scope, geo_scope = NULL, chunk_size = 50L, abstract_chars = 300L, verbose = TRUE)

Build a Taxonomic Screening Prompt for DataONE Datasets

Takes a geo-screened candidate tibble (or any catalog subset) and a plain- language description of the target taxonomic group, and builds one or more LLM prompt strings asking whether each dataset plausibly contains records for that group.

| Param | Required | Default | Doc |
|---|---|---|---|
| catalog | yes |  | A tibble of candidate datasets -- typically the output of parse_geo_screening_response filtered to geo_match == TRUE, or any subset of the full catalog produced by harvest_dataone_catalog. Must contain columns id and at least one of title, abstract, keywords. |
| taxon_scope | yes |  | Character string (length 1). Plain-language description of the target taxonomic group. Can be a common name, formal taxon name, or a short phrase, e.g. "marine fish", "Actinopterygii", "marine invertebrates", "vascular plants", "birds". The LLM will interpret this description and apply it to the dataset metadata. |
| geo_scope | no | NULL | Character string (length 1) or NULL (default). When supplied, the prompt additionally asks the LLM to assess geographic relevance, and parse_taxon_screening_response returns a geo_match column alongside taxon_match. Use this for literature catalogs (e.g. from search_literature) where build_geo_prompt cannot be used because the catalog lacks DataONE-specific columns. Example: "Santa Barbara Channel, southern California coastal waters". Leave NULL for the DataONE path. |
| chunk_size | no | 50L | Integer. Maximum datasets per prompt chunk. Default 50L. Smaller than the geo prompt default because title + abstract text is longer than geographic descriptions. |
| abstract_chars | no | 300L | Integer. Maximum characters from the abstract to include per dataset. Default 300L. Set to 0L to omit abstracts entirely (faster, less accurate). |
| verbose | no | TRUE | Logical. Report dataset counts and skipped entries. Default TRUE. |

**Value:** An object of classes 'c("taxon_prompt", "llm_prompt")', a named list with elements: prompts List of prompt strings, one per chunk. chunks List of character vectors of dataset IDs, one per chunk. n_chunks Integer. n_items Integer. Number of datasets submitted to the LLM. ids Character vector. All dataset IDs submitted (in order matching the LLM index column). skipped_ids Character vector. Dataset IDs excluded because title, abstract, and keywords are all missing. taxon_scope The 'taxon_scope' string as supplied. geo_scope The 'geo_scope' string, or 'NULL'. catalog The input catalog, for joining results back.

#### Details

The LLM is given each dataset's title, abstract (truncated), and keywords as evidence. Datasets with none of these fields populated are excluded from LLM screening and flagged in $skipped_ids.

Returns a taxon_prompt S3 object (also inheriting llm_prompt) that can be passed directly to prompt_api or prompt_manual.

Evidence used: The prompt includes title, truncated abstract, and keywords for each dataset. This is more informative than geographicdescription alone for taxonomic inference. Column names are matched case-insensitively; missing columns are silently treated as blank.

Bias towards inclusion: As with geographic screening, the prompt instructs the LLM to answer YES when uncertain. The intent is to avoid discarding datasets that have relevant records but vague metadata -- the EML screening and preview stages downstream will apply stricter filters.

No deduplication: Unlike geographic screening, title + abstract content is usually unique per dataset, so deduplication is not applied.

### call_api_pdf(prompt, pdf_path, sections = c("methods", "results", "appendix"), page_map = NULL, dpi = 150L, provider = NULL, tier = c("mid", "fast", "top"), model = NULL, max_tokens = 4000L, api_key = NULL, base_url = NULL, verbose = TRUE)

Send Selected PDF Pages to an LLM Vision API

Renders selected pages of a PDF as PNG images and sends them to a vision-capable LLM together with a text prompt. Returns the model's response as a single character string, compatible with all downstream parse functions.

| Param | Required | Default | Doc |
|---|---|---|---|
| prompt | yes |  | Character string. The extraction or characterization prompt to send along with the page images. This is the text part of the message; the images follow as separate content blocks. |
| pdf_path | yes |  | Character string. Path to the PDF file. |
| sections | no | c("methods", "results", "appendix") | Character vector. Section labels whose pages should be rendered and sent. Default c("methods", "results", "appendix"). Only sections present in page_map are used; others are silently skipped. Pass "all" to send the entire document (expensive). |
| page_map | no | NULL | Named list mapping section labels to integer page vectors, as returned in extract_pdf_text()$page_map. If NULL (default), extract_pdf_text() is called internally. Pass a pre-computed page_map to avoid re-parsing the PDF when Stage 2 has already run. |
| dpi | no | 150L | Integer. Rendering resolution in dots per inch. Default 150L. Increase to 200L or 300L for PDFs with small table fonts; decrease to 100L to reduce token cost when tables are large-print. |
| provider | no | NULL | Character. LLM provider name: "anthropic", "gemini", "openai", "ollama", or any provider registered with register_provider. Default NULL reads options("TaxaID.provider"), set automatically by library(TaxaTools). |
| tier | no | c("mid", "fast", "top") | Character. Model capability tier when model = NULL: "fast", "mid" (default), or "top". For vision tasks, "mid" or "top" is recommended. |
| model | no | NULL | Character. Exact model identifier. Overrides tier resolution. Use to pin a specific version, e.g. "claude-sonnet-4-6" or "gpt-4o". |
| max_tokens | no | 4000L | Integer. Maximum response tokens. Default 4000L. Increase for papers with many species-locality records. |
| api_key | no | NULL | Character. API key override. Default NULL reads the key from the environment variable for the resolved provider (e.g. ANTHROPIC_API_KEY). Keyless providers (Ollama) ignore this. |
| base_url | no | NULL | Character. Base URL override for OpenAI-compatible providers (Ollama, custom proxies). Default NULL. |
| verbose | no | TRUE | Logical. Report page counts and section selection. Default TRUE. |

**Value:** Character string. The raw text response from the model, suitable for passing directly to 'parse_pdf_extract_response' or 'screen_pdf_structure'. The '"model"' and '"provider"' attributes from 'call_api' are preserved on the return value.

#### Details

This is the Stage 3 engine for the PDF occurrence pipeline. Stages 1 and 2 use extract_pdf_text (text only, no API call). Stage 3 uses this function to send the methods and results pages as images, giving the model full visual fidelity on tables and layout.

Dispatches via call_api, so the provider is resolved from options("TaxaID.provider") by default. Any vision-capable provider works: Anthropic (Claude Sonnet/Opus), Gemini (2.5 Flash/Pro), OpenAI (GPT-4o), or a local Ollama vision model such as llava-llama3.

Page selection: Only pages belonging to the requested sections (as determined by .detect_pdf_sections) are rendered and sent. For a typical 15-page methods paper this reduces the page count from ~15 to ~5, saving approximately 15,000 input tokens per call.

Page ordering: Pages are sent in document order regardless of section order, so the model sees a coherent reading sequence.

No-header fallback: If section headers were not detected (has_headers = FALSE), all pages are sent regardless of the sections argument, and a warning is issued.

Token cost estimate: At 150 dpi, each page image is approximately 1,500-2,000 input tokens. A 5-page targeted send costs roughly 8,000-10,000 input tokens plus the prompt.

Provider and model selection: The function dispatches through call_api, so provider resolution, model tier lookup, and API key reading follow the same rules as all other TaxaID LLM calls. Set options(TaxaID.provider = "gemini") to switch providers session-wide, or pass provider explicitly for a single call.

### check_geographic_outliers(local_occurrences, min_local_n = 5L, min_occs = 7L, method = "distance", tdi = 1000, mltpl = 5, year_range = .gbif_default_year_range(), cache_dir = tools::R_user_dir("TaxaFetch", "cache"), candidate_taxa = NULL, candidate_scope = c("genus", "species", "all"), verdict_cache = TRUE, verbose = FALSE, on_cap = c("escalate", "warn", "error"))

Flag Geographically Isolated Occurrence Records Against a Species' Global Range

A bbox-scoped GBIF search (see 'get_gbif_occurrences') can return a single occurrence for a species that is genuinely absent from the study region - a misidentification, mislabeled specimen, or bad georeference elsewhere in GBIF, sitting far from that species' real range. This function targets exactly that case: for species with few local records, it fetches that species' unrestricted global GBIF occurrences ('geometry = NULL', see 'fetch_gbif_occurrences') and tests whether the local record(s) are geographic outliers against that global cloud, via 'CoordinateCleaner::cc_outl()'. Species ...

| Param | Required | Default | Doc |
|---|---|---|---|
| local_occurrences | yes |  | A data frame of bbox-scoped GBIF occurrence records (e.g. the output of get_gbif_occurrences or filter_gbif_quality). Must contain gbifID, species, speciesKey, decimalLatitude, and decimalLongitude. |
| min_local_n | no | 5L | Integer. Species with fewer than this many records in local_occurrences are checked against their global distribution. Species at or above this count are left untested. Default 5L. |
| min_occs | no | 7L | Integer. Minimum number of geographically unique global datapoints required before a species is actually tested by cc_outl() -- below this, dispersion statistics are unreliable and the species is reported as untested rather than silently passed. Matches CoordinateCleaner::cc_outl()'s own default. Default 7L. |
| method | no | "distance" | Character. cc_outl()'s outlier-detection method: "distance" (default here) flags a record whose nearest-neighbour distance to another same-species record exceeds tdi -- the most directly interpretable choice for "isolated from every cluster." "quantile" and "mad" are also available; see CoordinateCleaner::cc_outl() for their definitions. Only one of tdi (for "distance") or mltpl (for "quantile"/"mad") is used, depending on method. |
| tdi | no | 1000 | Numeric. Distance threshold in km, used only when method = "distance". Matches cc_outl()'s own default, 1000. |
| mltpl | no | 5 | Numeric. Interquartile-range/MAD multiplier, used only when method = "quantile" or "mad". Matches cc_outl()'s own default, 5. |
| year_range | no | .gbif_default_year_range() | Character. Year range for the global GBIF fetch, "YYYY,YYYY". Default "2000" through the current year (computed at call time), matching fetch_gbif_occurrences's own default. The global fetch characterizes the species' broader distribution, not just the local study window -- widen this if a narrow year range risks under-sampling a species' real range. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Forwarded to fetch_gbif_occurrences for checkpointing the global fetch. Default tools::R_user_dir("TaxaFetch", "cache"). |
| candidate_taxa | no | NULL | Optional character vector of taxa that can actually be ASSIGNED -- typically the species-level match candidates (e.g. unique(match_obj$taxon_name)). NULL (default) checks every locally-rare species in the pool. Supplying it is strongly recommended for a family-derived occurrence pool: at real PtConception 18S only 387 of 7,392 pool species (5.2%) were match candidates, so 95% of the per-species GBIF requests protected against a harm those species cannot cause. A species with 1-4 local records has a theta far below TaxaAssign::join_priors()'s expansion_min_prior, so it can never be expanded into a hypothesis; its only residual effect is +1 to the Good-Turing f1. A locally-rare MATCH CANDIDATE is the opposite: its prior multiplies its likelihood directly, which is the misidentified-record failure this check exists for. |
| candidate_scope | no | c("genus", "species", "all") | How candidate_taxa restricts the check. "genus" (default) keeps any locally-rare species sharing a genus with a candidate -- congeners matter because TaxaLikely::restore_suppressed_candidates() and expand_unreferenced_hypotheses() can promote one into a named hypothesis. "species" keeps only exact candidates (tightest). "all" ignores candidate_taxa entirely. Family scoping is deliberately not offered: an occurrence pool fetched from family keys already contains only candidate families, so it would restrict nothing. |
| verdict_cache | no | TRUE | Logical, default TRUE. Cache the per-record VERDICTS rather than the global occurrence cloud. The cloud is reduced to one integer per species and one logical per local record and then discarded, so caching it stores millions of records to preserve a few thousand numbers. The verdict file is keyed on a content hash (rlang::hash()) of the sorted species-key set, the requested local gbifIDs, and every parameter that changes the verdict (year_range, method, min_occs, tdi, mltpl, on_cap), so changing any of them recomputes. The file also records the keys whose global cloud was truncated (attr(, "capped_keys")), the fetch backend and the fetch date. The file name is the key, so a verdict file written under any other key -- including one from a TaxaFetch version that keyed on fewer inputs -- is never matched, and the first such run re-fetches every global cloud. A loaded cache file that shares none of the current call's requested gbifIDs (a stale or foreign file) is treated as a miss and recomputed, with a message() naming the skipped file. |
| verbose | no | FALSE | Logical. Forwarded to cc_outl(). Default FALSE. |
| on_cap | no | c("escalate", "warn", "error") | Character, forwarded to get_gbif_occurrences: what to do when a species' global fetch returns exactly the direct API's per-key limit (10,000) and was therefore TRUNCATED. Fewer than key_threshold (50) rare species use the direct API, and a truncated cloud is GBIF's return order, a non-random prefix -- the very reference this test measures "normal range" against. "escalate" (default) re-fetches the capped species through the download API with no limit; it needs GBIF credentials and falls back to a warning without them. "warn" keeps the truncated cloud and warns; "error" stops. Escalation downloads a species' full GLOBAL record set, which for a globally common species can run to millions of records. |

**Value:** 'local_occurrences' with three columns added, and 'attr(, "capped_keys")': the species keys whose verdict came from a truncated global cloud ('integer(0)' when none): 'local_n' Number of records for this species in 'local_occurrences'. 'global_n_unique' Number of geographically unique global records found for this species. 'NA' for species never checked ('local_n >= min_local_n'). 'outlier_status' One of '"not_tested_sufficient_local_data"' (local_n >= min_local_n, never checked), '"insufficient_global_data"' (checked, but fewer than 'min_occs' unique global points - cannot compute a reliable dispersion statistic), '"outlier"' (flagged by 'cc_outl()'), or '"consistent"' (checked, not flagged). Never a bare logical - "not tested" and "tested and passed" are kept distinct throughout, mirroring 'check_inat_range''s 'range_status' convention. *Edge case:* a row whose 'species' is 'NA' can never match 'rare_species' ('NA %in% x' is always 'FALSE'), so it is left at its initial '"not_tested_sufficient_local_data"' value - the same status a genuinely well-supported species gets. It means "unknown identity, never checked" here, not "checked and fine"; treat it as untestable for a different reason than a rare species, not as a passed check.

#### Details

Why this needs a global fetch at all: local_occurrences comes from a bbox-scoped GBIF search, so a species with one local record has nothing else in the same dataset to compare it against -- cc_outl() needs a real distribution, not one point. The global fetch is gated to only the species below min_local_n, since a well-supported local species needs no such check and the global fetch is the expensive step. This is a targeted, per-species-rare extension of fetch_gbif_occurrences (geometry = NULL) -- see that function for rate-limit/retry/checkpoint behavior, all inherited unchanged here.

min_occs is a real floor, not a formality: a species with too few unique global points (even after the global fetch) simply cannot support a reliable outlier test -- cc_outl() itself passes such species by default rather than testing them. This function makes that distinction explicit via "insufficient_global_data" rather than folding it into "consistent", so a downstream consumer never mistakes "we couldn't check" for "we checked and it's fine."

cc_outl() is called once per species, not once for the whole batch: confirmed on real production data that its "distance" method silently switches EVERY species in a single call to a coarser raster approximation whenever ANY ONE species in that call has 10,000 or more records. A species rare in the local bbox can still be globally common, so calling cc_outl() once across every rare species let one common species silently degrade every other species' precision -- this cleared a real, obvious ~9,000 km outlier (a Mugu Pseudotolithus epipercus record) on first live use. Per-species calls scope that raster decision to each species' own record count, where it belongs; the extra R-level call overhead is negligible next to the GBIF fetch itself.

### check_inat_range(taxon_names, lat, lng, api_token = Sys.getenv("INAT_API_TOKEN"), cache_dir = NULL, verbose = FALSE)

Check whether taxa fall within iNaturalist range polygons

For each taxon name, resolves the iNaturalist taxon ID, downloads the corresponding geomodel range polygon from iNaturalist's S3 bucket, and tests whether a query point (lat/lng) falls within the polygon. The range polygons are thresholded binary outputs of iNaturalist's SINR geomodel - the continuous probability surface is not publicly available.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of species names to check. |
| lat | yes |  | Numeric. Latitude of the query point in decimal degrees. |
| lng | yes |  | Numeric. Longitude of the query point in decimal degrees. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. iNaturalist API token for taxon name resolution. Defaults to the INAT_API_TOKEN environment variable. Generate a token at https://www.inaturalist.org/users/api_token (requires a free iNaturalist account; log in, then visit that URL to get a token good for 24 hours) and store it via Sys.setenv(INAT_API_TOKEN = "your_token") or in ~/.Renviron. |
| cache_dir | no | NULL | Character. Optional path to a directory for caching downloaded GeoJSON files. Speeds up repeated calls for the same taxa. |
| verbose | no | FALSE | Logical. If TRUE, prints progress for each taxon. Default FALSE. |

**Value:** A tibble with columns 'taxon_name', 'taxon_id', 'matched_name', 'name_match' (does the resolved iNat name equal the query, case-insensitively - FALSE flags a fuzzy-match resolution to a DIFFERENT taxon, which must never drive a prior elevation), 'rank', 'iconic_taxon_name', 'inat_kingdom', 'n_observations', 'in_range', 'range_status'. 'inat_kingdom' is derived from 'iconic_taxon_name' via a fixed lookup (no additional API call); compare against your own occurrence-database kingdom to detect taxon name collisions (e.g. a clam name matching a fungal genus).

#### Details

Intended for use on the dark diversity set: taxa detected by any method but absent from the regional occurrence database (i.e. lacking a TaxaExpect prior). Evidence is asymmetric: in_range = TRUE warrants a prior boost; in_range = FALSE should not suppress priors (false negatives are common for aquatic taxa due to low iNaturalist observer effort in marine systems). Use n_observations to gate the boost -- geomodel reliability scales with observation count. in_range = NA (no polygon exists) is neutral.

### dedupe_occurrences(occurrence_data, collapse_duplicate_occasions = TRUE, taxon_col = "scientificName", date_col = "eventDate", lat_col = "decimalLatitude", lon_col = "decimalLongitude", coord_precision = 3L)

Remove Duplicate Occurrence Records

Removes duplicate occurrence records from a single data frame via two independent mechanisms - an exact-ID match on 'gbifID', and a content-based match on species x date x coarse location. Deliberately separate from 'stack_occurrences': deduplication is relevant whether or not you are combining multiple sources, since duplicates can occur entirely within a single fetch (see Details) - a caller with only one data source has no reason to skip this step, unlike 'stack_occurrences' itself.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A single data frame of occurrence records, typically the output of get_gbif_occurrences, stack_occurrences, or any other TaxaFetch source function. |
| collapse_duplicate_occasions | no | TRUE | Logical. Default TRUE. Collapse rows describing the same species x date x location detection occasion to one row, keeping the first. Unlike the gbifID check below (an exact-ID match, unambiguous), this is a content-based match -- see Details for what it is for and why it defaults on. |
| taxon_col | no | "scientificName" | Character. Name of the taxon-identity column used to key collapse_duplicate_occasions. Default "scientificName" -- every current TaxaFetch source (GBIF, DataONE, BioTime, literature/PDF) already produces this column under this exact name. Ignored if collapse_duplicate_occasions = FALSE. |
| date_col | no | "eventDate" | Character. Name of the date column used to key collapse_duplicate_occasions. Default "eventDate". Falls back to a year/month/day triple (constructed as "YYYY-MM-DD") for any row where date_col is absent or NA -- needed because get_gbif_occurrences()'s "standard" column set carries year/month/day but not eventDate itself. Ignored if collapse_duplicate_occasions = FALSE. |
| lat_col | no | "decimalLatitude" | Character. Name of the latitude column, used to key collapse_duplicate_occasions. Default "decimalLatitude". |
| lon_col | no | "decimalLongitude" | Character. Name of the longitude column, used to key collapse_duplicate_occasions. Default "decimalLongitude". |
| coord_precision | no | 3L | Integer. Decimal places lat_col/lon_col are rounded to before matching in collapse_duplicate_occasions. Default 3 (~111 m at the equator). Ignored if collapse_duplicate_occasions = FALSE. |

**Value:** 'occurrence_data' as a tibble with duplicate rows removed. If a 'report_params' attribute is present (as attached by 'stack_occurrences'), its 'n_records' entry is refreshed to the post-dedup row count and a 'n_duplicates_removed' entry is added.

#### Details

gbifID deduplication: If occurrence_data has a gbifID column, rows with a duplicated non-NA gbifID are dropped (first occurrence kept). This is defense-in-depth against the same GBIF record being counted twice -- e.g. two queries with overlapping search geometry, or one call querying overlapping taxon keys -- since neither get_gbif_occurrences nor filter_gbif_quality dedupe records themselves. Sources without a gbifID column (e.g. literature or DataONE occurrences) are unaffected.

Duplicate detection occasions (collapse_duplicate_occasions): a different problem than the gbifID check above. That check catches the identical GBIF record entering twice; this one catches different records -- often from different platforms and observers -- that describe the same underlying detection event. GBIF aggregates eBird, iNaturalist, Observation.org, OBIS, and museum collections (see get_gbif_occurrences's own Details), and citizen-science platforms routinely produce many independent reports of one detection (dozens of eBird checklists for one rare bird; a dozen iNaturalist uploads from one bioblitz). Each is a distinct gbifID, so the check above does not touch them, but not a distinct occasion on which the species was documented. This can all happen inside one get_gbif_occurrences() call, so a caller with only one data source is not exempt.

This matters beyond bookkeeping: TaxaExpect::prepare_model_dataframe() counts raw records (dplyr::n()) as both n_species (the binomial numerator for a taxon at a site) and n_total_at_site (the shared effort denominator across every taxon at that site). Uncollapsed repeat reports of one individual therefore inflate that species' modeled relative detection frequency directly. Collapsing to one row per unique combination of taxon_col (case-insensitive), date_col (or year/month/day when date_col is absent), and lat_col/lon_col rounded to coord_precision answers the occupancy-modeling question this ecosystem actually wants: was the species documented here, on this occasion -- not how many people documented it.

Only rows with a non-missing value for every key component participate -- a row missing taxon_col, both date_col and year/month/day, or either coordinate (including a present column holding NA for that row) is always kept, never dropped on incomplete information. This is a content-based match, not an exact-ID match like gbifID -- it can only ever produce false negatives (a real duplicate occasion missed, e.g. differing date precision or coordinate rounding across platforms), never false positives, since two records agreeing on species, date, and location to ~100 m are extremely unlikely to be genuinely independent occasions. Set collapse_duplicate_occasions = FALSE to keep one row per raw report instead (e.g. if you deliberately want observer-effort/reporting-volume as your own signal, rather than TaxaExpect's occupancy framing).

Missing columns: occurrence_data is a data table, and a missing key column is a data problem, not something to silently paper over. The two checks differ in what counts as "missing":

- gbifID is genuinely optional -- sources without it (e.g. literature or DataONE occurrences) are expected, so when it is absent that check is simply skipped, with no message.

- When collapse_duplicate_occasions = TRUE (the default), taxon_col, date_col (or a full year/month/day triple), lat_col, and lon_col are all required as columns -- they are named parameters with documented defaults, not optional metadata. If any is absent from occurrence_data, the function stop()s immediately, naming the missing column(s) and the columns actually present, rather than silently skipping the step. Set collapse_duplicate_occasions = FALSE to skip this step entirely on a source that genuinely lacks these columns.

### download_gbif_occurrences(keys, geometry, year_range = .gbif_default_year_range(), limit = NULL, on_cap = c("warn", "error"), cache_dir = tools::R_user_dir("TaxaFetch", "cache"), overwrite = FALSE, pending_max_age_days = 30, submit_attempts = 4L, submit_wait = c(15, 30, 60), on_submit_failure = c("use_cache", "error"), prompt_mb = 50, cache_prompt_mb = 5120, allow_prompts = FALSE, keep_zip = TRUE, status_ping = 15, exclude_absent = TRUE, basis_keep = NULL, select_cols = c("kingdom", "phylum", "class", "order", "family", "genus", "species",      "infraspecificEpithet", "taxonRank", "scientificName", "taxonKey",      "speciesKey", "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",      "countryCode", "stateProvince", "year", "month", "day", "basisOfRecord",      "issue", "occurrenceStatus", "samplingProtocol", "occurrenceRemarks",      "preparations", "gbifID", "datasetKey", "license"), gbif_user = Sys.getenv("GBIF_USER"), gbif_pwd = Sys.getenv("GBIF_PWD"), gbif_email = Sys.getenv("GBIF_EMAIL"), beep = FALSE)

Download GBIF Occurrence Records via the Async Download API

Submits a bulk download request to GBIF, polls until the file is ready, downloads the result, and returns a tibble compatible with 'fetch_gbif_occurrences' output. Requires a free GBIF account.

| Param | Required | Default | Doc |
|---|---|---|---|
| keys | yes |  | Integer or numeric vector. GBIF taxon usage keys. Typically the output of get_keys_from_context or rgbif::name_backbone(). Duplicates are removed before processing. |
| geometry | yes |  | Character or NULL. A WKT polygon string defining the geographic search area. Use make_bbox_wkt to generate from a centre lat/lon and radius. Note: GBIF requires counter-clockwise winding order; make_bbox_wkt produces the correct winding order automatically. NULL issues an UNRESTRICTED global download -- the pred_within predicate is omitted and the cache signs as g0 -- matching fetch_gbif_occurrences's contract, so get_gbif_occurrences can route a global query (e.g. check_geographic_outliers's) to whichever backend its key count calls for. A global query can be very large; the pre-download summary reports its size and record count before any bytes are transferred. |
| year_range | no | .gbif_default_year_range() | Character. Year range formatted as "YYYY,YYYY", e.g. "2000,2024". Passed to GBIF as year >= and year <= predicates. Default "2000" through the current year, computed at call time -- not a fixed year that would silently go stale. |
| limit | no | NULL | Integer or NULL. Maximum records to retain per taxon key after import, matching the per-key semantics of fetch_gbif_occurrences. Records are kept in GBIF's return order; a message reports how many keys were truncated. NULL (default) retains all records for every key. When taxonKey is absent from the download, the cap is applied to the total row count instead, with a warning. |
| on_cap | no | c("warn", "error") | Character. What to do when limit actually truncates a taxon key. "warn" (default) raises a warning naming the affected keys and records them in attr(result, "capped_keys"); "error" stops. Truncation keeps GBIF's return order -- a non-random prefix -- so both abundance and spatial pattern become unreliable for capped taxa; prefer limit = NULL, which costs nothing since the records are already downloaded. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Directory for the downloaded zip file and a small metadata file. Defaults to a persistent user-level cache directory. Re-running with the same arguments reuses the cached zip and skips the GBIF download entirely. Set to NULL to disable caching. |
| overwrite | no | FALSE | Logical. If FALSE (default), an existing cached zip is reused. Set to TRUE to force a fresh download from GBIF -- in an interactive session this asks for confirmation first (showing the cached zip's date and size) before deleting it; a non-interactive session proceeds straight to a fresh download. Either way, the old cached zip is removed once the new one is saved -- it is never silently orphaned on disk. |
| pending_max_age_days | no | 30 | Numeric or NULL (default 30). A download key recorded in the cache metadata as pending (see GBIF outages below) is normally polled and re-fetched on the next call. When that record is older than this many days, it is instead abandoned WITHOUT polling it -- a message names the key and its age -- and a fresh request is submitted in the same call, since GBIF has almost certainly killed, cancelled, or purged a prepared download that old. NULL disables the age check, so a pending key is always polled first no matter how old. |
| submit_attempts | no | 4L | Integer (default 4). How many times the download request is submitted (and, separately, how many times the prepared file is fetched) before giving up when GBIF answers with a transient server-side failure (HTTP 5xx such as "503 Backend fetch failed", gateway errors, timeouts). Non-transient errors (bad credentials, a malformed predicate) are raised immediately, never retried. |
| submit_wait | no | c(15, 30, 60) | Numeric vector of seconds (default c(15, 30, 60)) slept between submission attempts; the last value repeats if submit_attempts exceeds its length. |
| on_submit_failure | no | c("use_cache", "error") | "use_cache" (default) or "error". What to do when every submission attempt -- or every attempt to fetch the prepared file (curl timeouts, resets, truncated transfers) -- fails AND a verified cached zip for this exact query exists (only possible with overwrite = TRUE, since the default already reuses such a zip without asking GBIF at all). "use_cache" imports that zip with a loud warning() naming the failure, the cache date and the download key, and sets attr(result, "served_from_cache_after_failure") = TRUE; the cached zip is kept as the live cache. "error" raises the failure instead. With no usable cached zip the function always errors. |
| prompt_mb | no | 50 | Numeric. In an INTERACTIVE session, a prepared download at least this many MB triggers a summary (size, record count, whether a zip for this exact query is already cached, what the cache holds now and will hold afterwards) and a choice: use the cache, download and replace it, or abort to narrow the query first. Smaller downloads proceed silently, and a NON-interactive session never blocks -- it reports the same facts and continues. Default 50; Inf disables the prompt entirely. The summary is placed before any bytes are transferred, because GBIF reports a prepared download's size and record count at that point, which is the only moment the information can still change the decision. |
| cache_prompt_mb | no | 5120 | Numeric. After a run, if the cache directory exceeds this many MB, an interactive session is offered a choice to free space (leave it; remove OTHER downloads but keep this query's zip; remove everything). A non-interactive session only reports. Default 5120 (5 GB); Inf disables the prompt while keeping the size report. |
| allow_prompts | no | FALSE | Logical, default FALSE. Whether this function may BLOCK on an interactive utils::menu(). Off by default because a blocking prompt inside a function that is called from a script is unsafe: when RStudio runs or sources a script it queues the remaining lines as console input, and menu() consumes those lines as answers -- re-prompting on each one, and, far worse, SILENTLY SWALLOWING them so they never execute. With FALSE every decision is REPORTED with the exact command to act on it, and nothing blocks. Set TRUE only when calling this function by hand at the console. |
| keep_zip | no | TRUE | Logical, default TRUE. Whether to retain the downloaded zip in cache_dir after a successful import. The zip is pure redundancy once imported -- its only value is avoiding a re-download -- and it is by far the largest thing this package writes: on one real machine 38 zips accounted for 17 GB of a 17.05 GB cache, while every .rds checkpoint together came to 52 MB. With FALSE the zip is deleted after import and the small metadata file is KEPT, so a later identical call re-fetches the SAME prepared GBIF key -- no new request, no queue wait, just the transfer. Set FALSE when the caller persists the imported data itself (every workflow in this ecosystem saves a _raw_gbif.rds checkpoint, which makes the zip doubly redundant). |
| status_ping | no | 15 | Numeric. Seconds between download-status polls while waiting for GBIF to prepare the file. Default 15. Minimum enforced by rgbif is 3. |
| exclude_absent | no | TRUE | Logical. When TRUE (default), adds a server-side occurrenceStatus = PRESENT predicate, excluding explicit absence records before the file is built by GBIF. Systematic surveys (e.g., eBird, iNaturalist) can contribute large numbers of ABSENT rows that inflate the download size without providing presence data. Set to FALSE only if you need absence records. Changing this parameter changes the cache key and triggers a fresh download. |
| basis_keep | no | NULL | Character vector or NULL. When not NULL, adds a server-side basisOfRecord predicate to the GBIF download request, reducing the size of the downloaded zip. Only occurrence records with a basisOfRecord value in this vector are included. Typical values: "HUMAN_OBSERVATION", "MACHINE_OBSERVATION", "LIVING_SPECIMEN", "PRESERVED_SPECIMEN", "MATERIAL_SAMPLE". NULL (default) requests all basis types. Changing this parameter changes the cache key and triggers a fresh download. For projects (eDNA, camera-trap, acoustic, etc.) where you want only field observations, use c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION"). |
| select_cols | no | c("kingdom", "phylum", "class", "order", "family", "genus", "species",      "infraspecificEpithet", "taxonRank", "scientificName", "taxonKey",      "speciesKey", "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",      "countryCode", "stateProvince", "year", "month", "day", "basisOfRecord",      "issue", "occurrenceStatus", "samplingProtocol", "occurrenceRemarks",      "preparations", "gbifID", "datasetKey", "license") | Character vector or NULL. Columns to retain after import. Uses data.table::fread's select argument so only the named columns are read into memory, which is much faster for large files. Does not reduce the downloaded zip size; use basis_keep for that. NULL loads all columns. The default is a set of ~35 columns covering the full TaxaID pipeline (taxonomy, spatial, temporal, quality, the eDNA-detection exclusion filter, and backbone keys). Unrecognised column names are silently ignored. |
| gbif_user | no | Sys.getenv("GBIF_USER") | Character. GBIF username. Defaults to the GBIF_USER environment variable; see Details for setup. |
| gbif_pwd | no | Sys.getenv("GBIF_PWD") | Character. GBIF password. Defaults to the GBIF_PWD environment variable. |
| gbif_email | no | Sys.getenv("GBIF_EMAIL") | Character. GBIF registered email address. Defaults to the GBIF_EMAIL environment variable. |
| beep | no | FALSE | Logical. If TRUE and the beepr package is available, plays a sound on completion. Falls back to a system bell character if beepr is absent. Default FALSE. |

**Value:** A tibble of occurrence records. Column structure matches 'fetch_gbif_occurrences' for downstream compatibility with 'filter_gbif_quality' and 'stack_occurrences'. The 'bibliographicCitation' column contains the GBIF download DOI (or the download key if DOI lookup fails). A 'download_key' attribute stores the GBIF download key for citation purposes.

#### Details

When to use this function vs fetch_gbif_occurrences:

- Use download_gbif_occurrences for large taxon lists (roughly 50 or more keys), for any run where completeness matters (no per-key record cap), or when fetch_gbif_occurrences hits HTTP 429 rate-limit errors. Downloads are processed server-side so no per-key API calls are made from the client. A GBIF account is required.

- Use fetch_gbif_occurrences for small exploratory queries (fewer than roughly 50 keys), when you want immediate per-key progress feedback, or when you do not have a GBIF account.

GBIF account setup: Register for a free account at https://www.gbif.org/user/profile. Then add your credentials to ~/.Renviron (run usethis::edit_r_environ() to open the file):


```

GBIF_USER=your_username GBIF_PWD=your_password GBIF_EMAIL=your@email.com ```

Save the file and restart R. Verify with Sys.getenv("GBIF_USER"). You only need to do this once; the variables are loaded automatically at the start of every R session.

Caching: The zip file returned by GBIF is saved to cache_dir using a filename that encodes the call signature (key count, key checksum, geometry length, year range, and basis_keep). Changing any of these parameters automatically triggers a fresh download. The cached zip is permanent and survives R sessions -- delete it manually or set overwrite = TRUE to refresh. A small companion metadata file (_meta.rds) stores the GBIF download key and timestamp. select_cols is applied at import time and does not affect the cache key; the same zip can be re-imported with different column sets.

Rank-specific predicates: Unlike the occurrence search API (occ_data), the download API's taxonKey predicate is an exact match, not a hierarchical search. Querying by a family key returns only records where the occurrence's accepted taxon IS that family (i.e., identified only to family level), not records of species within it. download_gbif_occurrences avoids this by using an OR across familyKey, genusKey, speciesKey, and taxonKey, so records at all ranks within the queried taxa are returned.

Hierarchy validation: Each returned record is checked to confirm that one of its rank-specific key columns (taxonKey, familyKey, genusKey, speciesKey, etc.) matches one of the requested keys. Off-target records are dropped with a diagnostic message.

GBIF outages: GBIF's API can return a 5xx during an outage. A production run that re-requests its occurrences on every run (overwrite = TRUE) would otherwise die at this step even with a verified zip for the identical query already on disk. Instead the request is retried with backoff (submit_attempts/submit_wait), and if GBIF is still refusing, on_submit_failure = "use_cache" falls back to that zip -- with a warning, never silently -- so the run completes on data that differ from a fresh pull only if GBIF's holdings changed since the cache was written. The status poll and the file fetch retry the same way. When a key has been issued but the poll or fetch still fails and there is no cache to fall back on, the key is recorded in the cache metadata as pending, and the next call re-fetches that prepared download instead of submitting a new request.

Dead pending keys: a pending record is cleared automatically once it can no longer be honoured (a key GBIF has killed, cancelled, failed, or purged server-side). Two mechanisms, both automatic: (1) a pending key older than pending_max_age_days is abandoned unpolled and a fresh request is submitted instead (see that parameter); (2) when the poll on a still-fresh pending key fails non-transiently, the dead record is cleared (the whole metadata file is removed when its zip was never obtained, the common case; otherwise the record is kept but marked no longer pending, so the real local zip is still served as an ordinary cache hit) and a fresh request is submitted automatically, in the same call -- no manual intervention needed. A brand-new key that itself fails to poll non-transiently is unaffected by this: that is still raised as an immediate error, since a first-time failure of that kind is a real problem.

Concurrent download limits: GBIF limits accounts to 3 concurrent downloads (fewer for accounts with many prior downloads). If a request is rejected, cancel in-progress downloads at https://www.gbif.org/user/download and retry.

#### Why nothing here blocks by default

A utils::menu() inside a function called from a sourced workflow script is dangerous: it can consume the ENTIRE remainder of the script as its answers -- every remaining line rejected as an invalid selection, each therefore never executed, even after the GBIF download itself has succeeded. RStudio queues the rest of a script as pending console input, and menu()/readline() read exactly that queue, so interactive() being TRUE says nothing about whether a human is waiting to type. Every decision here is therefore REPORTED, with the command to act on it, unless allow_prompts = TRUE is passed deliberately.

#### Attributes

Beyond download_key, the returned tibble always carries:

- report_params -- a list recording the call's own parameterization for downstream reporting: source (always "GBIF (async download)"), n_keys, n_records, doi (the download's DOI URL, or NA if lookup failed), geometry, and year_range.

- served_from_cache_after_failure -- logical, TRUE when every submission/fetch/poll attempt failed and a verified cached zip for this exact query was imported instead (see the on_submit_failure parameter); FALSE otherwise.

- capped_keys -- integer vector of taxon keys limit actually truncated (see the on_cap parameter); integer(0) when nothing was capped.

### download_literature_pdfs(catalog, output_dir, overwrite = FALSE, max_papers = NULL, pause_s = 0.5, verbose = TRUE)

Download PDFs for papers in a screened literature catalog

Downloads PDFs for rows in a 'search_literature' catalog tibble (or any downstream-filtered version of it) that have a non-'NA' 'pdf_url'. Adds a 'local_pdf_path' column so records feed directly into 'extract_pdf_text'.

| Param | Required | Default | Doc |
|---|---|---|---|
| catalog | yes |  | A tibble from search_literature, optionally filtered by parse_taxon_screening_response and/or parse_geo_screening_response. Must contain columns id and pdf_url. |
| output_dir | yes |  | Character. Directory where PDFs are saved. Created if it does not exist. |
| overwrite | no | FALSE | Logical. If FALSE (default), skip papers whose PDF already exists in output_dir. |
| max_papers | no | NULL | Integer or NULL. Cap the number of downloads. NULL (default) downloads all rows with a pdf_url. Useful for testing before committing to a full run. |
| pause_s | no | 0.5 | Numeric. Seconds to pause between downloads. Default 0.5. Publisher servers have rate limits; be polite. |
| verbose | no | TRUE | Logical. Print progress. Default TRUE. |

**Value:** The input 'catalog' with 'local_pdf_path' added. Rows where download failed or 'pdf_url' was 'NA' have 'local_pdf_path = NA_character_'. Pass the non-'NA' paths directly to 'extract_pdf_text': 'na.omit(result$local_pdf_path)'.

### extract_pdf_text(pdf_path, sections = .extract_sections, patterns = .section_patterns, max_header_chars = 80L, truncate_at_boundary = TRUE, verbose = TRUE)

Extract Text by Section from a PDF File

Uses 'pdftools' to extract plain text from a PDF, detects section boundaries using header matching, and returns the text of the requested sections as a named list. This is the lightweight first pass used in Stages 1 (screening) and 2 (characterization) of the PDF occurrence pipeline, before committing to more expensive API image calls.

| Param | Required | Default | Doc |
|---|---|---|---|
| pdf_path | yes |  | Character string. Path to a PDF file. |
| sections | no | .extract_sections | Character vector. Section labels to extract. Default .extract_sections: abstract, introduction, methods, results, appendix. Pass "all" to return all detected sections including discussion and references. |
| patterns | no | .section_patterns | Named list. Section header vocabulary. Default .section_patterns. Supply a custom list to handle non-standard section names (e.g. papers that use "Survey Methods" instead of "Methods"). |
| max_header_chars | no | 80L | Integer. Maximum line length to consider as a section header. Default 80L. |
| truncate_at_boundary | no | TRUE | Logical. If TRUE (default), detect and remove back matter belonging to other articles in the same PDF (e.g. journal volume indices, symposium announcements) before section detection runs. Uses journal citation header repeat and banner line repeat as triggers. Set to FALSE only if the document genuinely spans multiple articles that should all be extracted. |
| verbose | no | TRUE | Logical. Report detected sections and page counts. Default TRUE. |

**Value:** A named list with elements: sections Named list of character strings, one per requested section. Each string is the concatenated text of all pages in that section. Sections not detected in the document are absent. page_map Named list mapping section labels to integer vectors of page numbers (1-based). has_headers Logical. TRUE if section headers were detected. FALSE means the document has no explicit section structure and all pages were returned under "document". n_pages Integer. Total pages in the document. pdf_path The input path, for passing to downstream functions without re-specifying.

#### Details

Token management: This function performs no API calls. It is designed to be called once per PDF; its output is passed to screen_pdf_structure() (Stage 2), and call_api_pdf() (Stage 3) so the PDF is parsed only once.

No headers fallback: If no section headers are detected the entire document is returned under the key "document" and has_headers is FALSE. Downstream functions handle this gracefully by treating the full text as equivalent to the abstract + methods + results sections combined.

Relationship to DataONE pipeline: Analogous to fetch_dataone_eml(), which reads EML document structure to identify what content is present before committing to a full download. Here we read PDF structure to identify which pages contain which sections before committing to API image calls in Stage 3.

Dependencies: Requires the pdftools package (install.packages("pdftools")). The package is listed in Suggests, not Imports, because it is only needed for the PDF pipeline.

### fetch_dataone_occurrences(dataset_ids, bbox, extra_dwc_map = NULL, timeout = 120L, site_lookup = NULL, odm_variable = "DENSITY", verbose = TRUE)

Download and Standardize Occurrence Records from DataONE / EDI

Given a vector of EDI PASTA dataset identifiers (from 'search_dataone'), fetches and parses the EML metadata for each dataset, downloads data tables that contain coordinate and taxon columns, standardizes column names to Darwin Core, filters to the supplied bounding box, and optionally deduplicates against a GBIF occurrence snapshot. Returns a single tibble compatible with 'stack_occurrences'.

| Param | Required | Default | Doc |
|---|---|---|---|
| dataset_ids | yes |  | Character vector. One or more PASTA package identifiers, as returned in the id column of search_dataone, e.g. c("knb-lter-sbc.17.18", "knb-lter-sbc.50.9"). |
| bbox | yes |  | A named list with elements west, east, south, north (decimal degrees). Records outside this box are removed. Example: list(west = -121.0, east = -118.5, south = 33.5, north = 35.0). |
| extra_dwc_map | no | NULL | A data.frame with columns pattern and dwc_term, prepended before the default map so dataset-specific patterns take priority. NULL (default) uses the built-in map only. |
| timeout | no | 120L | Integer. HTTP download timeout in seconds for individual data table downloads. Default 120L. Increase to 600L or more for datasets with very large entity files (e.g. multi-hundred-MB event tables). |
| site_lookup | no | NULL | A data.frame with columns site_code, decimalLatitude, and decimalLongitude, or NULL (default). When supplied, overrides EML geographicCoverage point sites for multi-site coordinate injection. Use this when EML site codes do not match the site labels in the data (e.g. "BC" in EML vs "BC I", "BC II" in data). Applies to all datasets in the current call; for per-dataset overrides call fetch_dataone_occurrences separately for each dataset. |
| odm_variable | no | "DENSITY" | Character. The variable_name value to filter on when joining LTER Observation Data Model (ODM) tables. Default "DENSITY". Other common values: "PERCENT_COVER", "DRY_GM2", "AFDM". Set to NULL to keep all variable rows (produces long-format output with one row per taxon x location x date x variable). |
| verbose | no | TRUE | Logical. Print per-dataset and per-entity progress messages. Default TRUE. |

**Value:** A tibble with standardized Darwin Core columns, or 'NULL' invisibly if no records survive all filters. Column order: 'occurrenceID', 'datasetID', 'datasetName', 'institutionCode', 'basisOfRecord', 'eventDate', 'year', 'month', 'day', 'decimalLatitude', 'decimalLongitude', 'coordinateUncertaintyInMeters', 'scientificName', 'genus', 'family', 'specificEpithet', 'vernacularName', 'individualCount', 'recordedBy', 'locality', 'habitat'; followed by any unmapped source columns.

#### Details

EML parsing: EML is fetched from the PASTA metadata endpoint. Entity data URLs are extracted from <dataTable> and <otherEntity> nodes. Only entities whose EML attribute names map to both a latitude and longitude column are downloaded. Namespaces are stripped before XPath queries to handle both EML 2.1 and 2.2.

Column mapping: Raw column names are matched case-insensitively against the pattern column using first-match-wins regex. Unmapped columns are retained at the end of the tibble. Use extra_dwc_map to handle non-standard names without modifying package internals.

Date standardization: Existing eventDate columns are normalized to ISO 8601 (YYYY-MM-DD). If absent but year/month/day are present, eventDate is constructed from them.

Cross-source deduplication: this function does not dedupe against GBIF itself. If you combine this output with GBIF occurrences (e.g. via get_gbif_occurrences), pass both to stack_occurrences, whose collapse_duplicate_occasions (default TRUE) collapses records describing the same species x date x location detection occasion across sources -- see that function's Details for the full rationale.

### fetch_gbif_occurrence_counts(keys, site_lat, site_lon, geometry = NULL, lambda_km = NULL, breaks_km = NULL, year_range = .gbif_default_year_range(), basis_of_record = NULL, key_batch_size = 150L, resolve_names = TRUE, cache_dir = tools::R_user_dir("TaxaFetch", "cache"), max_active = 4L, base_url = "https://api.gbif.org/v1")

Fetch species-level GBIF record counts in distance bands around a site

The count-only counterpart of 'download_gbif_occurrences()': same taxon keys, same search polygon, same year filter - but instead of downloading every record it asks GBIF's occurrence-search API for per-species record COUNTS ('limit = 0', 'facet = speciesKey') inside a set of concentric distance bands around one site. The result feeds 'TaxaExpect::estimate_kernel_priors_from_counts()', which returns the same prior object 'TaxaExpect::estimate_kernel_priors()' does. The bands are centred on one site: 'site_lat' and 'site_lon' must be single numbers (a vector is rejected with an error), so ...

| Param | Required | Default | Doc |
|---|---|---|---|
| keys | yes |  | Numeric vector of GBIF backbone taxon keys defining the taxonomic scope -- the same keys you would pass to download_gbif_occurrences() (typically from get_keys_from_context()). Any rank; a record counts when any of its lineage keys matches. |
| site_lat | yes |  | Numeric scalars. Band centre. |
| site_lon | yes |  | Numeric scalars. Band centre. |
| geometry | no | NULL | Character WKT polygon or NULL. The search polygon (the same one the occurrence fetch uses); anticlockwise ring, as GBIF requires. NULL: bands only, no regional remainder band. |
| lambda_km | no | NULL | Numeric or NULL. Kernel bandwidth the counts will be used with; sets the default breaks_km. One of lambda_km / breaks_km is required. |
| breaks_km | no | NULL | Numeric vector or NULL. Increasing band outer edges, in km. Overrides the lambda_km default. |
| year_range | no | .gbif_default_year_range() | Character "YYYY,YYYY" or NULL (no year filter). Default: 2000 through the current year, as in fetch_gbif_occurrences(). |
| basis_of_record | no | NULL | Character vector or NULL (no filter), e.g. c("HUMAN_OBSERVATION", "PRESERVED_SPECIMEN"). |
| key_batch_size | no | 150L | Integer. Taxon keys per request (keys are OR-ed within a request; batches are disjoint and summed). Default 150 keeps URLs well under GBIF's limit. |
| resolve_names | no | TRUE | Logical. Look up each species key's name and classification (default TRUE). FALSE returns keys only. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Persistent cache for both the band counts (keyed by a hash of every argument that changes the answer) and the per-species-key classification. NULL disables caching. |
| max_active | no | 4L | Integer. Concurrent requests. Default 4. |
| base_url | no | "https://api.gbif.org/v1" | Character. GBIF API root. Exposed for testing. |

**Value:** A tibble with one row per species x band holding records: 'taxon_name' (GBIF canonical species name), 'speciesKey', 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'band', 'band_lo_km', 'band_hi_km', 'n'. Attributes: 'query' (the arguments), 'n_requests', 'n_species_lookups' (uncached classification lookups made by this call), 'total_records' (all species-level records counted), 'timing' (seconds), 'fetched_at'.

#### Details

Cost is set by the number of bands and key batches, not by the number of records: every band is one request per batch of key_batch_size taxon keys, however many millions of records fall inside it. The one cost that does grow with the pool is naming it -- GBIF facets return species KEYS, so each distinct species key is looked up once (/v1/species/{key}) and kept in cache_dir for every later call.

#### What the counts do and don't carry

Only records resolved to species level are counted (the facet counts records by speciesKey), which is also what the kernel path keeps after filter_gbif_quality(require_species = TRUE). The server-side filters are occurrenceStatus = PRESENT, hasCoordinate = TRUE, hasGeospatialIssue = FALSE, plus year_range/basis_of_record. The record-level screens in filter_gbif_quality() (coordinate precision, coordinate uncertainty, institution proximity) and every per-record step downstream of it (habitat assignment by location, spatial review, a depth covariate) have no count-only equivalent and are not applied.

#### Bands

Band k holds the records whose distance to the site lies in (breaks_km[k-1], breaks_km[k]], obtained by differencing cumulative geoDistance counts. When geometry is supplied every band is ALSO clipped to it (GBIF combines the two filters with AND), and one extra band (band_hi_km = Inf) holds the rest of the polygon beyond the last break -- so summed over bands, each species' count equals its count in the polygon, which is the pool the kernel path's regional back-off uses. Default breaks, given lambda_km: lambda_km * c(0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 9). They include 3 * lambda_km, the kernel's default neighborhood-support radius (support_weight = exp(-3)), so singleton and doubleton counts are exact at that radius, and 6 * lambda_km, the kernel's fetch-radius check.

### fetch_gbif_occurrences(keys, geometry, year_range = .gbif_default_year_range(), limit = 10000L, chunk_size = 20L, pause_seconds = 2, pause_between_keys = 0.5, max_retries = 4L, cache_dir = tools::R_user_dir("TaxaFetch", "cache"), beep = FALSE)

Fetch GBIF Occurrence Records for a Set of Taxon Keys

Downloads occurrence records from GBIF for a vector of taxon usage keys, processing them in chunks to stay within API rate limits. Returns a single combined tibble of all records that pass hierarchy validation.

| Param | Required | Default | Doc |
|---|---|---|---|
| keys | yes |  | Integer or numeric vector. GBIF taxon usage keys. Typically the output of get_keys_from_context or rgbif::name_backbone(). Duplicates are removed before processing. |
| geometry | yes |  | Character or NULL. A WKT polygon string defining the geographic search area. Use make_bbox_wkt to generate from a centre lat/lon and radius. NULL issues an unrestricted global search instead -- useful for pulling a species' full range as a reference cloud (e.g. check_geographic_outliers), not for routine regional fetches. |
| year_range | no | .gbif_default_year_range() | Character or NULL. Year range for the GBIF query, formatted as "YYYY,YYYY", e.g. "2000,2024". Passed directly to rgbif::occ_data(year = ...). NULL issues no year filter at all (matches geometry = NULL's unrestricted-search convention). Default: "2000" through the current year, computed fresh at call time -- not a fixed year that would silently go stale. |
| limit | no | 10000L | Integer. Maximum records to return per taxon key. GBIF caps this at 100,000; default 10,000 is usually sufficient for regional queries. |
| chunk_size | no | 20L | Integer. Number of keys per API batch. Default 20. Reduce if you experience HTTP 429 rate-limit errors; increase cautiously. |
| pause_seconds | no | 2 | Numeric. Seconds to pause between chunks. Default 2. Increase to be polite to the API under heavy load. |
| pause_between_keys | no | 0.5 | Numeric. Seconds to pause between individual key requests within a chunk. Default 0.5. Increase if 429 errors persist. |
| max_retries | no | 4L | Integer. Maximum number of retry attempts per key on transient errors (429 or 503), using exponential backoff. Default 4. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Directory for checkpoint files. Defaults to a persistent user-level cache directory (tools::R_user_dir("TaxaFetch", "cache")). If a fetch is interrupted by a transient error, progress is saved as a checkpoint and re-running with the same arguments resumes from where it stopped. Set to NULL to disable checkpointing. |
| beep | no | FALSE | Logical. If TRUE and the beepr package is available, plays a sound on completion. Falls back to a system bell character if beepr is absent. Default FALSE. |

**Value:** A tibble of occurrence records with GBIF's standard columns. Only records where the query key appears somewhere in the returned record's taxonomic hierarchy are retained (see Details). Returns an empty tibble with a warning if no records pass.

#### Details

Hierarchy validation: GBIF sometimes returns records for synonyms or higher-rank ancestors of the queried key. Each returned record is checked to confirm that the query key appears somewhere in its taxonomic hierarchy columns (taxonKey, speciesKey, genusKey, familyKey, orderKey, classKey, phylumKey, kingdomKey, acceptedTaxonKey). Records that fail this check are silently dropped. This prevents off-target taxa from entering the dataset when searching at family or order level.

When to use this function vs download_gbif_occurrences:

- Use fetch_gbif_occurrences for small exploratory queries (fewer than roughly 50 keys), when you want immediate per-key progress feedback, or when you do not have a GBIF account.

- Use download_gbif_occurrences for large taxon lists (roughly 50 or more keys), when completeness matters (no per-key record cap), or when this function hits HTTP 429 rate-limit errors. The async download API processes requests server-side with no per-key rate limits. A free GBIF account is required.

Rate limiting and transient errors: HTTP 429 (rate limit) errors trigger exponential backoff with waits of 30, 60, 120, and 240 seconds per key. HTTP 503 (Service Unavailable) errors are retried with shorter waits (5, 10, 20, 40 seconds). If any key exhausts all retries, the function stops immediately to avoid returning an incomplete, session-inconsistent result. Progress is saved so re-running resumes from the last successful key. To test your connection interactively, run rgbif::occ_data(taxonKey = 1, limit = 1). If you see HTTP 429 errors frequently, increase pause_seconds or reduce chunk_size, or switch to download_gbif_occurrences.

Checkpoint / resume: Progress is saved after each completed chunk to cache_dir. The checkpoint file name encodes the call signature (number of keys, key sum, geometry length, year range, limit), so changing any parameter automatically starts a fresh fetch rather than loading a stale checkpoint. To force a fresh fetch with the same parameters, delete the checkpoint file (path is printed when a fetch is interrupted) or set cache_dir = NULL.

rgbif dependency: This function requires the rgbif package, listed under Suggests rather than Imports because downstream modeling functions do not require it. Install with install.packages("rgbif").

### fetch_inat_occurrence_counts(taxon_names, lat, lng, radius_km = 50, captive = c("any", "true", "false"), quality_grade = c("any", "casual", "needs_id", "research"), api_token = Sys.getenv("INAT_API_TOKEN"), retry_attempts = 4L, retry_wait = c(15, 30, 60), verbose = FALSE)

Fetch local iNaturalist observation counts, including casual-grade records

For each taxon name, resolves the iNaturalist taxon ID and counts observations within a radius of a query point, via iNaturalist's '/v1/observations' search endpoint. Unlike 'check_inat_range' (which tests a point against a thresholded geomodel range polygon), this function counts real, individual observation records - including, by default, 'quality_grade = "casual"' and 'captive = "any"' records that standard GBIF-style occurrence indexing structurally excludes or under-indexes (captive pets/livestock, cultivated/ornamental plants).

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of species names to check. |
| lat | yes |  | Numeric. Latitude of the query point in decimal degrees. |
| lng | yes |  | Numeric. Longitude of the query point in decimal degrees. |
| radius_km | no | 50 | Numeric. Search radius in kilometers. Default 50. iNaturalist's API caps this at 500. |
| captive | no | c("any", "true", "false") | Character, one of "any" (default), "true", "false". Filters on iNaturalist's own captive/cultivated flag -- "true" isolates exactly the captive/cultivated records GBIF-style filtering excludes; "any" includes both. |
| quality_grade | no | c("any", "casual", "needs_id", "research") | Character, one of "any" (default), "casual", "needs_id", "research". "casual" is where iNaturalist routes most captive/cultivated observations, but is not identical to captive = "true" -- a wild organism with poor evidence is also casual grade. Use captive, not quality_grade, to isolate captive/cultivated status specifically. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. iNaturalist API token for taxon name resolution. Defaults to the INAT_API_TOKEN environment variable. |
| retry_attempts | no | 4L | Integer (default 4L). How many times the observation-count request is attempted in total before giving up when iNaturalist answers with a 429 (rate limit) or 5xx (server error). Matches download_gbif_occurrences's submit_attempts convention. Any other status (including a success or a 401) is never retried. |
| retry_wait | no | c(15, 30, 60) | Numeric vector of seconds (default c(15, 30, 60)) slept between retry attempts when iNaturalist does not send a Retry-After header; the last value repeats if retry_attempts exceeds its length. A server-sent Retry-After value, when present, is honoured instead. |
| verbose | no | FALSE | Logical. If TRUE, prints progress for each taxon. Default FALSE. |

**Value:** A tibble with columns 'taxon_name', 'taxon_id', 'matched_name', 'inat_kingdom' (derived from iNaturalist's own 'iconic_taxon_name' via the same fixed lookup 'check_inat_range' uses - compare against your own candidate's kingdom before trusting a result: iNaturalist resolves names against its own curated taxonomy, not NCBI's or GBIF's, so a name that matches an unrelated homonym in a different kingdom is possible, if rare; a kingdom mismatch is a strong signal to discard the result rather than act on it), 'n_observations_local', 'query_status' ('"ok"' or '"taxon_not_found"'), 'radius_km', 'captive', 'quality_grade'.

#### Details

Intended as a non-GBIF occurrence source for domestic/commensal/food species (see TaxaExpect::generate_domestic_food_priors()), where GBIF's own occurrence indexing under-counts exactly the organisms this function is meant to detect. Set quality_grade = "research" and captive = "false" to reproduce something closer to GBIF-style filtering for comparison.

This function counts observations only -- it does not download individual records. The iNaturalist API returns total_results on every search response regardless of per_page, so a single lightweight request (per_page = 1) is sufficient per taxon.

Retry/backoff: a 429 (rate limit) or 5xx (server error) response from the observation-count request is retried up to 4 attempts total, honouring a server-sent Retry-After header when present and falling back to a 15/30/60 s backoff otherwise. Once every attempt is exhausted, that taxon's row still gets query_status = "request_failed" -- retrying only reduces how often a transient rate-limit/outage produces that outcome, it does not change what a persistent failure looks like to the caller.

Omission implements "any": captive = "any" and quality_grade = "any" are implemented by OMITTING the corresponding query parameter from the /v1/observations request entirely (see .inat_observation_count()), not by sending an explicit captive=any/quality_grade=any value. Verified against the live API (Turdus migratorius, per_page = 1, so only total_results was compared): both parameters omitted returns total_results = 470344; adding quality_grade=research returns 434444 (omission is the strict superset, as "any" should be); and sending captive=any explicitly, with quality_grade still omitted, also returns 470344 -- identical to leaving captive out altogether. Omitting a parameter and sending it explicitly as "any" are the same query.

### filter_gbif_quality(data, basis_keep = c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION", "LIVING_SPECIMEN",      "PRESERVED_SPECIMEN"), exclude_edna = TRUE, exclude_absent = TRUE, bad_issues = c("COORDINATE_OUT_OF_RANGE", "COUNTRY_COORDINATE_MISMATCH", "COORDINATE_INVALID",      "ZERO_COORDINATE", "COORDINATE_PRECISION_INVALID"), max_coord_uncertainty = 500, max_coord_decimal_places = NULL, require_species = FALSE, exclude_equal_coords = TRUE, exclude_near_zero = TRUE, near_zero_buffer_m = 5000, exclude_near_gbif_hq = TRUE, exclude_country_centroid = TRUE, exclude_capital = TRUE, flag_institution = TRUE)

Filter GBIF Occurrence Records by Quality

Removes low-quality rows from a raw GBIF occurrence download. Applies up to twelve sequential filters: coordinate completeness, absent occurrences, basis of record, geospatial issue codes, coordinate uncertainty, coordinate decimal-place precision, eDNA/metabarcoding keyword removal, species-level requirement, and six 'CoordinateCleaner'-backed checks (identical lat/lon, near-zero coordinates, near GBIF headquarters, near a country/province centroid, near a national capital, near a biodiversity institution). Each filter is applied only when the relevant column (or package) is present; ...

| Param | Required | Default | Doc |
|---|---|---|---|
| data | yes |  | A data frame of GBIF occurrence records. Must contain decimalLatitude and decimalLongitude. |
| basis_keep | no | c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION", "LIVING_SPECIMEN",      "PRESERVED_SPECIMEN") | Character vector. Values of basisOfRecord to retain. Records not in this vector are removed. Default retains human and machine observations and specimen records; excludes fossil and unknown sources. |
| exclude_edna | no | TRUE | Logical. If TRUE (default), records whose samplingProtocol, occurrenceRemarks, or preparations columns contain eDNA or metabarcoding keywords are removed. Set to FALSE if your workflow specifically targets eDNA data. This option is sequence-specific by design: it removes GBIF records that are themselves eDNA detections so an eDNA study's priors are not built from other eDNA detections, and it has no image/acoustic counterpart because none is needed -- GBIF does not carry a comparably reliable self-labeling signal for those modalities. |
| exclude_absent | no | TRUE | Logical. If TRUE (default), records where occurrenceStatus is "ABSENT" (case-insensitive) are removed. GBIF downloads can include explicit absence records from systematic surveys where a species was searched for but not found; these are non-detections and must not be used as presence data for priors or occurrence modelling. If the occurrenceStatus column is absent the filter is skipped silently. |
| bad_issues | no | c("COORDINATE_OUT_OF_RANGE", "COUNTRY_COORDINATE_MISMATCH", "COORDINATE_INVALID",      "ZERO_COORDINATE", "COORDINATE_PRECISION_INVALID") | Character vector. GBIF issue codes that indicate likely geospatial errors. Records whose issues field contains any of these codes are removed. Default covers the most consequential spatial errors; see Details for how to check which codes appear in your data. |
| max_coord_uncertainty | no | 500 | Numeric. Maximum allowable value of coordinateUncertaintyInMeters in metres (default 500). Records with a value exceeding this threshold are removed. The 500 m default is a commonly used GBIF quality threshold, stricter than GBIF's own default but appropriate for ecological analyses where grid cell sizes are typically 10+ km. Set to 1000 for coarser analyses or Inf to disable. Records where coordinateUncertaintyInMeters is NA are retained (uncertainty not reported is not the same as uncertainty being large). If the column is absent the filter is skipped with a message. |
| max_coord_decimal_places | no | NULL | Integer or NULL. Minimum number of decimal places required in at least one coordinate (latitude or longitude). Records where both coordinates are rounded to fewer decimal places than this threshold are removed as likely imprecise. NULL (default) disables this filter. 1 decimal place ~ 11 km resolution 2 decimal places ~ 1 km resolution 3 decimal places ~ 111 m resolution Recommended: 2 or 3 for habitat grids on the order of a few hundred metres to a kilometre. |
| require_species | no | FALSE | Logical. If TRUE, records where the species column is NA or empty are removed. Default FALSE. Set to TRUE when querying GBIF by family or genus key: GBIF returns records at all taxonomic ranks within the queried taxon, including observations identified only to family or genus level. Those coarse-rank records lack a species value and are unusable downstream in TaxaAssign. If the species column is absent, this filter is skipped with a message. |
| exclude_equal_coords | no | TRUE | Logical. If TRUE (default), records where decimalLatitude exactly equals decimalLongitude are removed (CoordinateCleaner::cc_equ()) -- a common data-entry/field-swap signature. Skipped with a message if the CoordinateCleaner package is not installed. |
| exclude_near_zero | no | TRUE | Logical. If TRUE (default), records near the (0, 0) "Null Island" point are removed (CoordinateCleaner::cc_zero()), using that function's own default buffer. This catches near-zero coordinates that fall short of GBIF's own exact-zero ZERO_COORDINATE issue flag. Skipped with a message if CoordinateCleaner is not installed. |
| near_zero_buffer_m | no | 5000 | Numeric. Radius in METRES around (0, 0) within which a record counts as a null-island artifact. Default 5000. This is passed explicitly and must stay that way. CoordinateCleaner::cc_zero()'s own default is 0.5, which only made sense when its buffer was in DEGREES; in CoordinateCleaner 3.x the units are METRES, so relying on that default silently reduces this check to "within half a metre of (0,0)" and it stops catching anything. Verified against CoordinateCleaner 3.0.1: a record at (0.02, 0.01), about 2.5 km from null island, survives at buffer = 0.5 and at 1000, and is only caught at 5000. Every other cc_* function this function calls already defaults in metres (cc_gbif 1000, cc_cen 1000, cc_cap 10000, cc_inst 100), so cc_zero is the outlier. 5000 is chosen to catch (0,0) itself plus the coordinate-rounding and truncation noise that produces most null-island records, while staying small enough not to discard genuine records from the Gulf of Guinea, which is real ocean and a legitimate sampling location. |
| exclude_near_gbif_hq | no | TRUE | Logical. If TRUE (default), records near GBIF's Copenhagen headquarters are removed (CoordinateCleaner::cc_gbif()), using that function's own default buffer -- catches a known GBIF pathology where a failed geocode silently defaults to GBIF's own office coordinates. Skipped with a message if CoordinateCleaner is not installed. |
| exclude_country_centroid | no | TRUE | Logical. If TRUE (default), records near a country or province centroid are removed (CoordinateCleaner::cc_cen()), using that function's own default buffer and bundled reference data (test = "both") -- catches coarse/administrative-level georeferencing that silently snapped to a centroid instead of a true locality. Skipped with a message if CoordinateCleaner is not installed. |
| exclude_capital | no | TRUE | Logical. If TRUE (default), records near a national capital are removed (CoordinateCleaner::cc_cap()), using that function's own default buffer and bundled reference data -- a related, wider-radius version of the same coarse-georeferencing pathology exclude_country_centroid targets. Skipped with a message if CoordinateCleaner is not installed. |
| flag_institution | no | TRUE | Logical. If TRUE (default), records near a biodiversity institution (museum, zoo, herbarium, university) are flagged, not removed (CoordinateCleaner::cc_inst()), using that function's own default buffer and bundled ~10,000-location reference table. Unlike every other CoordinateCleaner check in this function, proximity to an institution is not treated as an unambiguous error: field stations and marine labs are frequently sited exactly where good habitat is, so a nearby record may be a genuine wild observation, not an archived/captive specimen -- that judgment call needs a human (and often a map), not a silent drop. Adds six columns to the retained data (see Value): institution_flag, institution_name, institution_type, institution_dist_m, institution_lon, institution_lat (the matched institution's own location, distinct from the record's own coordinates -- lets a downstream map-review tool plot both together). Skipped with a message if CoordinateCleaner is not installed. |

**Value:** The input data frame with low-quality rows removed. Column structure is unchanged. A summary message reports the number of records retained. Every removed record is also preserved, not just counted: 'attr(result, "removed_records")' is a data frame with the same columns as the input plus 'filter_reason', one row per removed record (always present, possibly zero rows - never 'NULL', so it can be inspected unconditionally). 'filter_reason' identifies which filter removed the record: '"missing_coordinates"', '"absent_occurrence"', '"basis_of_record"', '"flagged_issue_code:<code>"' (the specific 'bad_issues' code that matched, not just that one did), '"coordinate_uncertainty"', '"coordinate_decimal_precision"', '"edna_keyword"', '"no_species_id"', or one or more of '"equal_coordinates"' / '"near_zero"' / '"near_gbif_hq"' / '"country_centroid"' / '"capital"' joined with '";"' when a 'CoordinateCleaner' record was flagged by more than one of those five checks at once. A record is removed by exactly the filter that catches it first (filters run sequentially - see Details), except within the 'CoordinateCleaner' removal step itself, where several checks run against the same surviving data and any that flag a given record are all recorded together. Institution proximity is deliberately never a 'filter_reason' value - see the next paragraph. Separately, the *retained* data frame itself gains six columns when 'flag_institution = TRUE' (the default): 'institution_flag' (logical), 'institution_name', 'institution_type', 'institution_dist_m' (metres, to the nearest match), and 'institution_lon'/'institution_lat' (that institution's own coordinates). Unlike everything in 'removed_records', these rows are never removed - proximity to a biodiversity institution is flagged for human review, not treated as an automatic error. See 'flag_institution''s own documentation below for why.

#### Details

Filter order: Coordinates -> absent occurrences -> basis of record -> issue codes -> coordinate uncertainty -> coordinate decimal-place precision -> eDNA -> species-level requirement -> CoordinateCleaner removal checks (equal coordinates / near-zero / near GBIF HQ / near a country or province centroid / near a national capital) -> institution flagging (retained, not removed). Applying cheaper filters first reduces unnecessary string operations on large datasets.

Why keep the removed records at all: two users who ran this function with different arguments (a different max_coord_uncertainty, a different bad_issues set, CoordinateCleaner installed or not) can otherwise get silently different results with no way to compare notes. attr(result, "removed_records") makes that difference inspectable rather than invisible, and doubles as a direct list of candidate real GBIF data-quality problems (mislabelled coordinates, institution/centroid-snapped georeferencing) worth reporting back to the original data provider -- every original column, including gbifID and datasetKey, is preserved on each removed record for exactly that purpose.

CoordinateCleaner checks use that package's own defaults: this function deliberately does not hard-code any of cc_zero()'s, cc_gbif()'s, cc_cen()'s, cc_cap()'s, or cc_inst()'s buffers, reference coordinates, or reference data itself -- all are called directly with only lon/lat/ value supplied (cc_cen()/cc_cap()/cc_inst() resolve their own ref = NULL default to that package's bundled countryref/institutions data automatically, with no network call), so any future correction to those defaults in CoordinateCleaner is inherited automatically rather than silently diverging from a hand-copied constant.

Verifying issue codes in your data:


```

sort(table(unlist(strsplit(na.omit(your_data$issues), ";"))), decreasing = TRUE) ```

Decimal-place precision (OR logic): A record is retained if either its latitude or its longitude has at least max_coord_decimal_places decimal places. This avoids discarding records on coastlines or grid boundaries where one coordinate may be rounded while the other is precise.

### get_gbif_occurrences(keys, geometry, year_range = .gbif_default_year_range(), limit = NULL, key_threshold = 50L, rank_filter = "species", columns = "standard", cache_dir = tools::R_user_dir("TaxaFetch", "cache"), overwrite = FALSE, exclude_absent = TRUE, basis_keep = NULL, status_ping = 15, gbif_user = Sys.getenv("GBIF_USER"), gbif_pwd = Sys.getenv("GBIF_PWD"), gbif_email = Sys.getenv("GBIF_EMAIL"), chunk_size = 20L, pause_seconds = 2, pause_between_keys = 0.5, max_retries = 4L, on_cap = c("warn", "escalate", "error"), beep = FALSE)

Fetch GBIF Occurrences - Unified Entry Point

Picks between 'fetch_gbif_occurrences' (direct API, small queries) and 'download_gbif_occurrences' (async bulk API, large queries) based on the number of distinct 'keys', then standardizes both paths' output to one column contract and, by default, filters to species-rank records. This is a thin wrapper - neither underlying function is modified; see Details for why they stay separate.

| Param | Required | Default | Doc |
|---|---|---|---|
| keys | yes |  | Integer or numeric vector. GBIF taxon usage keys, typically from get_keys_from_context. Duplicates are removed before the key count is compared to key_threshold. |
| geometry | yes |  | Character. WKT polygon (see make_bbox_wkt). |
| year_range | no | .gbif_default_year_range() | Character. "YYYY,YYYY". Default "2000" through the current year, computed at call time. |
| limit | no | NULL | Integer or NULL. Per-key record cap, forwarded as-is. NULL (default) means "retain all records" on the download path (its own default); on the fetch path, NULL is translated to that function's own default (10000L) since it does not accept NULL directly. |
| key_threshold | no | 50L | Integer. Number of distinct keys at or above which download_gbif_occurrences is used instead of fetch_gbif_occurrences. Default 50L, matching both functions' own documented guidance. Lower it if the fetch path is hitting HTTP 429 rate limits below 50 keys; raise it if you would rather have the fetch path's immediate per-key feedback for a somewhat larger query and have a stable connection. |
| rank_filter | no | "species" | Character or FALSE/NULL. "species" (default) keeps only records where taxonRank exactly equals this value (case-insensitive) -- occurrences above species rank (family/genus-only identifications) are not usable by downstream taxon-level modelling (TaxaHabitat / TaxaExpect) and every existing caller already drops them post hoc. Because this is an exact match, not a "species or finer" match, records GBIF ranks SUBSPECIES, VARIETY, or FORM are also dropped by the default, even though they carry a usable species-level identity in their own species column -- deliberately conservative rather than a bug, but worth knowing if a query returns fewer records than expected for a taxon with many subspecies-level GBIF identifications. Set to FALSE or NULL to disable. See Details for why this is always a post-fetch filter, never a GBIF query predicate. |
| columns | no | "standard" | Character. "standard" (default) trims and reorders the output to a curated column set covering the spatial / temporal / taxonomic / quality fields used by filter_gbif_quality and stack_occurrences -- see filter_gbif_quality and Details below for the exact list and a known asymmetry. "all" skips trimming entirely (passes select_cols = NULL to download_gbif_occurrences; no trim on the fetch path -- you get whatever each backend natively returns). A character vector requests a custom column set instead; columns unavailable from the backend that fired are filled with NA rather than dropped, so the returned column set always matches what was requested. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Forwarded to whichever backend fires. Default tools::R_user_dir("TaxaFetch", "cache"). |
| overwrite | no | FALSE | Logical. Forwarded to download_gbif_occurrences only (no zip cache to overwrite on the fetch path). Default FALSE. |
| exclude_absent | no | TRUE | Forwarded to download_gbif_occurrences when that path fires; see its own documentation. Ignored on the fetch path. |
| basis_keep | no | NULL | Forwarded to download_gbif_occurrences when that path fires; see its own documentation. Ignored on the fetch path. |
| status_ping | no | 15 | Forwarded to download_gbif_occurrences when that path fires; see its own documentation. Ignored on the fetch path. |
| gbif_user | no | Sys.getenv("GBIF_USER") | Forwarded to download_gbif_occurrences when that path fires; see its own documentation. Ignored on the fetch path. |
| gbif_pwd | no | Sys.getenv("GBIF_PWD") | Forwarded to download_gbif_occurrences when that path fires; see its own documentation. Ignored on the fetch path. |
| gbif_email | no | Sys.getenv("GBIF_EMAIL") | Forwarded to download_gbif_occurrences when that path fires; see its own documentation. Ignored on the fetch path. |
| chunk_size | no | 20L | Forwarded to fetch_gbif_occurrences when that path fires; see its own documentation. Ignored on the download path. |
| pause_seconds | no | 2 | Forwarded to fetch_gbif_occurrences when that path fires; see its own documentation. Ignored on the download path. |
| pause_between_keys | no | 0.5 | Forwarded to fetch_gbif_occurrences when that path fires; see its own documentation. Ignored on the download path. |
| max_retries | no | 4L | Forwarded to fetch_gbif_occurrences when that path fires; see its own documentation. Ignored on the download path. |
| on_cap | no | c("warn", "escalate", "error") | Character. What to do when any taxon key returns exactly the per-key limit -- i.e. was TRUNCATED. Truncated records are GBIF's own return order, a non-random prefix, so abundance and spatial pattern both become unreliable for those taxa. "warn" (default) warns and records the keys in attr(result, "capped_keys"); "escalate" re-fetches the affected keys through the download API with limit = NULL (needs GBIF credentials; falls back to a warning); "error" stops. |
| beep | no | FALSE | Logical. Forwarded to whichever backend fires. Default FALSE. |

**Value:** A tibble. When 'columns != "all"', the column set and order are identical regardless of which backend produced the data (missing columns are 'NA'-filled, not dropped) - see Details for the two backend fields that are always 'NA' on the download path specifically. Compatible with 'filter_gbif_quality' and 'stack_occurrences'.

#### Details

Why GBIF, and not a separate fetcher per citizen-science/museum platform: GBIF is an aggregator, not just one more data source among many -- it already ingests and republishes records from eBird, iNaturalist, Observation.org, OBIS, and most natural history museum/ herbarium collections, each as its own registered dataset/publisher, alongside data GBIF itself mobilizes directly. Any record from those platforms that has been published to GBIF already arrives through this one function with no extra code -- writing a dedicated fetcher for one of those platforms would just re-fetch a subset of what this call already returns. A separate, platform-specific function is only justified when that platform has data GBIF genuinely does not carry -- e.g. check_inat_range calls iNaturalist's own geomodel API for range polygons, a data type no GBIF occurrence record includes at all, rather than duplicating iNaturalist's occurrence records themselves (already available here via GBIF).

Why a wrapper, not one merged function: the two backends have genuinely different execution models. fetch_gbif_occurrences is client-paced with per-key retries and needs no GBIF account; its cost grows roughly with key count and carries real rate-limit (HTTP 429) risk at high key counts. download_gbif_occurrences is server-side and account-gated, with a largely fixed queue/prep overhead that does not scale down -- a poor trade for a handful of keys, the right one for hundreds. Their parameter sets barely overlap (one has exclude_absent/basis_keep/GBIF credentials; the other has chunk_size/pause_seconds/max_retries). Rather than carry both sets in one function with half silently unused depending on path, this wrapper forwards the relevant subset to whichever backend actually runs and leaves both functions untouched.

Why the rank filter is always post-fetch: neither GBIF's download predicate API nor occ_data's search parameters expose a taxonomic-rank field (confirmed against rgbif's own predicate key vocabulary) -- there is no server-side lever to send. The filter is therefore always applied here, after the data comes back, identically regardless of which backend produced it. It reduces R-side memory/size, not GBIF's query cost.

Column standardization and a known, unfixable asymmetry: the "standard" column list (see TaxaFetch:::.gbif_standard_columns()) is aligned across both backends. download_gbif_occurrences already renames the download path's SIMPLE_CSV quality-issue column from issue (singular) to issues (plural, matching the search API used by fetch_gbif_occurrences and what filter_gbif_quality checks for) before returning -- this wrapper only translates the requested issues column name back to issue when building select_cols for the download path, since select_cols is matched against the SIMPLE_CSV's native column names at import time, before that rename happens. One asymmetry remains and is not fixable here:

- familyKey/genusKey are NA on the download path. GBIF's SIMPLE_CSV format does not include these fields at all (they are DWCA-only), so there is nothing to rename or select -- they are genuinely absent upstream. fetch_gbif_occurrences output has them populated.

- Similarly, samplingProtocol/occurrenceRemarks/ preparations (used by filter_gbif_quality(exclude_edna = TRUE)) are not present in GBIF's SIMPLE_CSV export either, and so are NA on the download path; they are included when present on the fetch path.

### get_keys_from_context(hierarchy_df)

Fetch GBIF Taxon Keys Using Full Taxonomic Context

Resolves a dataframe of scientific names to GBIF usage keys by supplying the full taxonomic hierarchy (kingdom, phylum, class, etc.) as context to the GBIF name backbone API. Providing hierarchy context prevents homonym errors where identical names refer to different organisms in different kingdoms.

| Param | Required | Default | Doc |
|---|---|---|---|
| hierarchy_df | yes |  | A dataframe. Each row is one taxon. Columns should be named for Linnaean ranks (case-insensitive): kingdom, phylum, class, order, family, genus, species. Not all ranks need to be present. For each row, the most specific rank provided is used as the lookup target; higher ranks are passed as disambiguation context. |

**Value:** The input dataframe with three columns appended: usageKey Integer. GBIF usage key for the matched name, or 'NA' if no match was found. matchType Character. GBIF match quality: '"EXACT"', '"FUZZY"', '"HIGHERRANK"', '"LOOKUP_RECOVERED"' (a '"HIGHERRANK"' result recovered via a secondary 'name_lookup()' call - see '@details'), '"NONE"', '"NO_DATA"' (no rank columns present in this row), or '"ERROR"' (API call failed). gbif_rank Character. The rank GBIF assigned to the matched record, or 'NA' if no match.

#### Details

Homonym prevention: Many scientific names are valid in multiple kingdoms (e.g., Alaria is both a brown alga and a trematode worm). Supplying the full hierarchy ensures GBIF resolves the name to the correct lineage. Rows that provide only a species name with no higher-rank context may return incorrect matches for homonyms.

Target rank selection: For each row the function identifies the most specific non-empty rank (species > genus > family > order > class > phylum > kingdom) and treats it as the lookup target. Column names are matched case-insensitively, so Kingdom, KINGDOM, and kingdom all work.

Errors and missing matches: API failures for individual rows produce a warning and return matchType = "ERROR" for that row rather than stopping the entire run. Review rows with matchType %in% c("NONE", "FUZZY", "ERROR", "LOOKUP_RECOVERED") before downstream use -- "LOOKUP_RECOVERED" rows were resolved by a secondary, less-precise lookup (narrowed by kingdom when available, but not guaranteed correct for homonyms; see the Homonym prevention section above) and deserve the same scrutiny as a "FUZZY" match.

rgbif: This function requires the rgbif package, listed under Suggests because it is only needed for the data-ingest portion of the pipeline. Install with install.packages("rgbif").

### harvest_dataone_catalog(cache_file = "pasta_catalog.rds", max_age_days = 7, max_rows = Inf, page_size = 500L, exclude_noise = TRUE, pause_seconds = 0.5, verbose = TRUE)

Harvest the Full PASTA / EDI Dataset Catalog

Downloads metadata for all non-noise packages from the PASTA Solr endpoint and returns them as a tibble. Results are cached to disk; subsequent calls within 'max_age_days' return the cache without hitting the network.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_file | no | "pasta_catalog.rds" | Character. Path to an .rds cache file. If the file exists and is younger than max_age_days, the cache is returned without any network requests. Set to NULL to disable caching. Default "pasta_catalog.rds". |
| max_age_days | no | 7 | Numeric. Maximum age of a valid cache in days. Default 7. |
| max_rows | no | Inf | Integer. Maximum total records to retrieve. Set to Inf to retrieve all available records (may take 2-5 minutes on first run). Default Inf. |
| page_size | no | 500L | Integer. Records per Solr request. Default 500. Reduce if you encounter timeouts. |
| exclude_noise | no | TRUE | Logical. Exclude known non-biological scopes (ecotrends, lter-landsat*). Default TRUE. |
| pause_seconds | no | 0.5 | Numeric. Pause between paginated requests. Default 0.5. |
| verbose | no | TRUE | Logical. Print progress. Default TRUE. |

**Value:** A tibble with one row per PASTA package and columns: 'id', 'scope', 'title', 'site', 'pubdate', 'geographicdescription', 'taxonomic', 'abstract', 'keywords_str', 'authors', 'doi', 'begindate', 'enddate', 'has_taxonomic', 'is_candidate'. 'is_candidate' is 'TRUE' for packages that have a non-empty 'taxonomic' field and are therefore worth geographic screening.

#### Details

"PASTA" (the endpoint queried here, pasta.lternet.edu) is the data repository infrastructure operated by the https://edirepository.orgEnvironmental Data Initiative (EDI) -- not itself a dataset. Every package harvested here was published through EDI, and its terms of use ask that data be cited (a doi column is included below for this purpose) and that data providers be contacted before use in a publication; see https://edirepository.orgedirepository.org for the current policy. This function does not enforce or verify citation/contact compliance -- that remains the caller's responsibility.

This is the first step in the DataONE supplemental occurrence pipeline:


```

catalog <- harvest_dataone_catalog(cache_file = "pasta_catalog.rds") geo_prompt <- build_geo_prompt(catalog, bbox) llm_output <- prompt_api(geo_prompt) candidates <- parse_geo_screening_response(llm_output, geo_prompt) ```

Cache invalidation: Delete or rename the cache file to force a full re-download. The cache stores the raw tibble -- no further processing is done at cache-read time.

PASTA coordinates field: The Solr coordinates field is indexed but unreliably populated for most packages. Spatial filtering is handled downstream via screen_eml_columns (EML <boundingCoordinates>) and record-level bbox filtering in fetch_dataone_occurrences.

### make_bbox_wkt(lat, lon, radius_deg)

Create a WKT Bounding Box Around a Central Point

Generates a Well-Known Text (WKT) POLYGON string representing a square bounding box centred on a given latitude and longitude. The result is ready to pass directly to the 'geometry' argument of 'fetch_gbif_occurrences'.

| Param | Required | Default | Doc |
|---|---|---|---|
| lat | yes |  | Numeric. Latitude of the centre point in decimal degrees (WGS 84). Must be in the range [-90, 90]. |
| lon | yes |  | Numeric. Longitude of the centre point in decimal degrees (WGS 84). Must be in the range [-180, 180]. |
| radius_deg | yes |  | Numeric. Half-width of the bounding box in decimal degrees. The box extends radius_deg degrees in each direction from the centre, giving a total side length of 2 * radius_deg -- a square in degree-space, not in physical distance. Must be positive. For reference: 1 degree of latitude is approximately 111 km at any latitude; 0.5 degrees is approximately 55 km. This conversion holds only along the north-south axis. East-west, 1 degree of longitude shrinks by a factor of cos(latitude) (e.g. only about 78 km at 45 degrees latitude, about 39 km at 70 degrees), so the box's true east-west coverage is narrower than its north-south coverage away from the equator -- a real consideration for high- latitude sites. |

**Value:** A length-1 character vector: a WKT POLYGON string with vertices ordered counter-clockwise and the first and last vertex identical (closed ring), as required by the GBIF occurrence API.

#### Details

Square vs. irregular polygons: This function always produces a square bounding box. For an irregular boundary (coastline, watershed, administrative region) use define_search_polygon to draw a custom polygon interactively, or construct a WKT string manually and pass it directly to fetch_gbif_occurrences(geometry = ...).

Coordinate clamping: If the box would extend beyond the poles (lat +/- radius_deg outside [-90, 90]) or the antimeridian (lon +/- radius_deg outside [-180, 180]), the function stops with an informative error. Queries spanning the antimeridian are not supported by this helper; split them into two overlapping queries instead.

WKT coordinate order: WKT uses (longitude latitude) order -- i.e., X before Y -- which is the opposite of the common (lat, lon) convention. This function handles the swap internally; callers supply (lat, lon) as is conventional in this package.

### parse_geo_screening_response(raw_text, geo_prompt)

Parse an LLM Geographic Screening Response

Parses the raw text returned by an LLM in response to a 'build_geo_prompt' prompt, fans YES/NO decisions back to all datasets sharing each description, and returns a filtered tibble of candidate datasets.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character. Length-1 string containing the LLM response (from prompt_api or read_llm_response). |
| geo_prompt | yes |  | A geo_prompt object from build_geo_prompt. |

**Value:** A tibble with all columns from the input catalog plus: geo_match Logical. 'TRUE' = LLM said YES (or shortcut accepted); 'FALSE' = LLM said NO (or shortcut rejected). geo_source Character. One of '"llm_yes"', '"llm_no"', '"shortcut_accepted"', '"shortcut_rejected"', '"no_description"', '"llm_no_response"'. The tibble includes ALL candidate packages - filter on 'geo_match == TRUE' to obtain the candidate list for 'screen_eml_columns'.

#### Details

Expected LLM output format: A CSV with columns index and match, where index is the integer row number from the prompt and match is YES or NO. Markdown fences and preamble text are stripped automatically.

Shortcut packages (pre-accepted or pre-rejected by build_geo_prompt) are added back to the tibble automatically with appropriate geo_source values.

Non-candidate packages (those where is_candidate == FALSE in the catalog) are excluded from the return value -- use the original catalog to recover them.

### parse_pdf_extract_response(raw_text, extract_prompt)

Parse a raw LLM extraction response to a Darwin Core tibble

Parses the raw text returned by 'call_api_pdf()' into a tidy Darwin Core tibble compatible with 'stack_occurrences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character string. Raw response from call_api_pdf(). When chunked extraction was used, pass the concatenated responses as a single string before calling this function: paste(responses, collapse = "\n"). |
| extract_prompt | yes |  | A pdf_extract_prompt object from build_pdf_extract_prompt(). |

**Value:** A tibble with Darwin Core columns. Returns 'NULL' invisibly (with a warning) if parsing fails.

### parse_taxon_screening_response(raw_text, taxon_prompt)

Parse an LLM Taxonomic Screening Response

Parses the raw text returned by an LLM in response to a 'build_taxon_screen_prompt' prompt, matches YES/NO decisions back to dataset IDs, and returns the input catalog annotated with 'taxon_match' and 'taxon_source' columns.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character. Length-1 string containing the LLM response (from prompt_api or read_llm_response). |
| taxon_prompt | yes |  | A taxon_prompt object from build_taxon_screen_prompt. |

**Value:** A tibble with all columns from the input catalog plus: taxon_match Logical. 'TRUE' = LLM said YES for taxon; 'FALSE' = LLM said NO or no response received. taxon_source Character. One of '"llm_yes"', '"llm_no"', '"skipped"' (no metadata available), '"llm_no_response"' (index missing from LLM output). geo_match Logical. Only present when 'taxon_prompt' was built with a 'geo_scope' argument. 'TRUE' = LLM said YES for geographic relevance. Includes ALL input datasets - filter on 'taxon_match == TRUE' to obtain candidates for 'screen_eml_columns'.

#### Details

Expected LLM output format: A CSV with columns index and match, where index is the integer row number from the prompt and match is YES or NO. Markdown fences and preamble text are stripped automatically. Duplicate header rows from multi-chunk responses are handled automatically.

Skipped datasets (those in taxon_prompt$skipped_ids) are added back with taxon_match = FALSE and taxon_source = "skipped".

### plan_gbif_fetch(keys, geometry = NULL, lambda_km = NULL, breaks_km = NULL, year_range = .gbif_default_year_range(), basis_of_record = NULL, key_batch_size = 150L, cache_dir = tools::R_user_dir("TaxaFetch", "cache"), ram_gb = NULL, ram_fraction = 0.5, max_records = 5e+06, rates = list(), max_active = 4L, base_url = "https://api.gbif.org/v1")

Plan a GBIF fetch: price the records path against the counts path

Asks GBIF, with a handful of count-only requests, how big the occurrence pull for these keys, polygon and years would be, then prices both prior paths:

| Param | Required | Default | Doc |
|---|---|---|---|
| keys | yes |  | Numeric vector of GBIF backbone taxon keys defining the taxonomic scope -- the same keys you would pass to download_gbif_occurrences() (typically from get_keys_from_context()). Any rank; a record counts when any of its lineage keys matches. |
| geometry | no | NULL | Character WKT polygon or NULL. The search polygon (the same one the occurrence fetch uses); anticlockwise ring, as GBIF requires. NULL: bands only, no regional remainder band. |
| lambda_km | no | NULL | Numeric or NULL. Kernel bandwidth the counts will be used with; sets the default breaks_km. One of lambda_km / breaks_km is required. |
| breaks_km | no | NULL | Numeric vector or NULL. Increasing band outer edges, in km. Overrides the lambda_km default. |
| year_range | no | .gbif_default_year_range() | Character "YYYY,YYYY" or NULL (no year filter). Default: 2000 through the current year, as in fetch_gbif_occurrences(). |
| basis_of_record | no | NULL | Character vector or NULL (no filter), e.g. c("HUMAN_OBSERVATION", "PRESERVED_SPECIMEN"). |
| key_batch_size | no | 150L | Integer. Taxon keys per request (keys are OR-ed within a request; batches are disjoint and summed). Default 150 keeps URLs well under GBIF's limit. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Persistent cache for both the band counts (keyed by a hash of every argument that changes the answer) and the per-species-key classification. NULL disables caching. |
| ram_gb | no | NULL | Numeric or NULL. Physical memory to compare the record path's peak against. NULL: detected on macOS and Linux, otherwise NA (no memory-based recommendation). |
| ram_fraction | no | 0.5 | Numeric. Share of ram_gb the records path may use before the counts path is recommended. Default 0.5. |
| max_records | no | 5e+06 | Numeric. Pool size above which the counts path is recommended regardless of memory. Default 5 million. |
| rates | no | list() | Named list overriding any of the rates above. |
| max_active | no | 4L | Integer. Concurrent requests. Default 4. |
| base_url | no | "https://api.gbif.org/v1" | Character. GBIF API root. Exposed for testing. |

**Value:** A one-row tibble: 'n_records' (rows the records path would download), 'n_species_records' (of those, resolved to species), 'n_species', 'n_species_uncached', 'records_download_mb', 'records_queue_min', 'records_process_min', 'records_peak_gb', 'counts_requests', 'counts_min', 'ram_gb', 'recommended' ('"records"' or '"counts"') and 'reason'.

#### Which path

Choose by what the prior needs first and by size second. The records path is the only one that supports record-level habitat assignment, a covariate kernel (e.g. depth), bandwidth calibration (TaxaExpect::calibrate_kernel_bandwidth()), spatial review of individual records, and merging non-GBIF records (local surveys) into the same pool; if the analysis needs any of them, use it whenever it fits in memory. Otherwise the counts path gives the same kernel prior to within an order of magnitude for the species that matter, in seconds to minutes, and it is the only feasible path once the pool runs to many millions of records. The recommendation returned here applies that rule: counts when the records path's estimated peak memory exceeds ram_fraction of ram_gb or the pool exceeds max_records, records path otherwise.

#### Rates behind the estimates

Measured on the PtConception 18S pool (1.72 million records, Apple silicon laptop) and exposed as rates so they can be re-measured: download_bytes_per_record 410 (the zip), filter_sec_per_million 240 (filter_gbif_quality(), the dominant automated per-record step; habitat assignment and resolution together took under 10 s per 300,000 records), filter_gb_per_million 4 (peak R memory of filter_gbif_quality()), counts_sec_per_request 0.25 and name_lookups_per_sec 28 (the counts path's band requests and uncached species-name lookups), and download_queue_min 10 (GBIF's server-side preparation time; it varies with GBIF load and is the least predictable term). Not priced for either path: LLM habitat lookups per taxon (the same per-taxon cost on both paths, and cached) and, on the records path, interactive spatial review, which is paid in reviewer time per flagged point.

### preview_dataone_occurrences(dataset_ids, bbox, n_rows = 20L, large_mb = 50, assume_mbps = 5, extra_dwc_map = NULL, verbose = TRUE)

Preview DataONE/EDI Datasets Before Full Download

For each PASTA dataset ID, fetches EML metadata (fast), issues HEAD requests to obtain file sizes without downloading, then streams only the first 'n_rows' lines per entity to extract a sample taxon name and check bounding-box coverage. Automatically detects datasets with separate spatial and species tables (DwC Archive star schema) and reports them as joinable pairs rather than independent incomplete entities.

| Param | Required | Default | Doc |
|---|---|---|---|
| dataset_ids | yes |  | Character vector. PASTA package identifiers as returned in the resolved_id column of screen_eml_columns. |
| bbox | yes |  | Numeric vector c(west, east, south, north) or a named list with elements west, east, south, north (decimal degrees). |
| n_rows | no | 20L | Integer. Number of data rows to stream per entity. Default 20L. |
| large_mb | no | 50 | Numeric. File-size threshold (MB) separating "ready" from "large" status. Default 50. |
| assume_mbps | no | 5 | Numeric. Assumed download speed in MB/s for estimating download time. PASTA connections are typically 3--10 MB/s. Default 5. |
| extra_dwc_map | no | NULL | A data.frame with columns pattern and dwc_term, prepended before the default map. NULL (default) uses the built-in map only. |
| verbose | no | TRUE | Logical. Print per-dataset progress messages. Default TRUE. |

**Value:** A tibble of class 'c("dataone_preview", "tbl_df", "tbl", "data.frame")' with one row per entity (or joinable pair) and columns: dataset_id PASTA identifier, e.g. '"edi.653.8"'. dataset_title Full dataset title (not truncated). entity_name Entity (table) name; for joinable pairs formatted as '"entity_A + entity_B"'. status One of '"ready"', '"large"', '"skip"', '"join_ready"', or '"join_large"'. The 'join_*' values indicate that 'fetch_dataone_occurrences' will join two tables automatically. skip_reason Reason string; 'NA' unless 'status == "skip"'. file_mb File size in MB from 'Content-Length' header. For join pairs, the sum of both entity sizes. 'NA' for chunked responses. est_min Estimated download time in minutes. 'NA' when 'file_mb' is 'NA'. coord_source '"columns"', '"eml_sites"', or 'NA'. n_bbox Preview rows within 'bbox'. 'NA' for 'eml_sites' rows (bbox already confirmed by 'screen_eml_columns'). join_key Join column description for 'join_*' rows, e.g. '"shared id"' or '"event$id <-> occ$eventID"'. 'NA' for single-entity rows. first_taxon Scientific name from the first non-NA sample row. 'NA' when no usable rows were streamed. large_mb The 'large_mb' threshold used (stored for the print method). sample List-column of small preview tibbles (up to 'n_rows' rows, DWC-renamed). For join pairs, the joined sample. Inspect with 'prev$sample[[i]]'.

#### Details

Returns a tibble classed "dataone_preview" with one row per entity or joinable pair. The S3 print method groups rows into three sections -- READY, LARGE, SKIPPED -- and within each section groups by dataset, printing the full dataset title as a sub-header.

No full download required: sizes come from HTTP HEAD requests; only n_rows lines are streamed per entity.

Join detection: when a dataset has both a spatial-only and a species-only entity, the function attempts to identify a join key from the sample rows using the same strategies as fetch_dataone_occurrences. Detection may fail for sparse samples; fetch_dataone_occurrences will still attempt the join on the full data regardless.

### read_biotime_study(local_path = NULL, study_id = NULL, verbose = TRUE)

Read and DwC-map a downloaded BioTime study CSV

Reads a single-study occurrence CSV downloaded from the BioTime database and returns a Darwin Core-mapped tibble compatible with 'stack_occurrences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| local_path | no | NULL | Character scalar or NULL. Path to the downloaded BioTime study CSV. If NULL (the default), a system file-chooser dialog is opened so you can navigate to the file interactively. Passing a path directly is recommended for reproducible scripts. |
| study_id | no | NULL | Character or integer scalar or NULL. The BioTime STUDY_ID for this file (e.g. 595L or "595"). Used to populate the datasetID column as "biotime:<study_id>". If NULL, the numeric portion of the filename is used when the filename matches the pattern raw_data_<id>.csv; otherwise datasetID is set to "biotime:unknown" with a warning. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A tibble with Darwin Core columns plus BioTime-specific passthroughs, compatible with 'stack_occurrences()': 'scientificName' Character. From 'valid_name'. 'decimalLatitude' Numeric. 'decimalLongitude' Numeric. 'year' Integer. 'month' Integer or NA. 'day' Integer or NA. 'occurrenceStatus' Character. '"present"', '"absent"', or 'NA' (neither 'ABUNDANCE' nor 'BIOMAS' parsed to a number for this row). 'organismQuantity' Numeric. ABUNDANCE value. 'organismQuantityType' Character. '"abundance"'. 'eventID' Character. BioTime SAMPLE_DESC value. 'datasetID' Character. '"biotime:<study_id>"'. 'basisOfRecord' Character. '"HumanObservation"'. 'biotime_biomass' Numeric. BIOMAS value (passthrough).

#### Obtaining BioTime data

BioTime (https://biotime.st-andrews.ac.uk) is a global database of biodiversity time-series assembled from published studies. Data are provided as per-study CSVs -- one file per study -- and are not available via a query API. To download a study:

- Go to https://biotime.st-andrews.ac.uk/home.php and register for a free account.

- Browse or search the study list to find studies relevant to your taxon and region. Each study has a numeric STUDY_ID (e.g. 595).

- On the study page, click Download data to save the CSV (typically named raw_data_<STUDY_ID>.csv).

- Note the STUDY_ID -- pass it to the study_id argument so that datasetID is populated correctly in the output.

Citation: BioTime requires that you cite both the database and the original study. The DOI for the BioTime database is 10.1111/geb.12729 (Dornelas et al. 2018, Global Ecology and Biogeography). Per-study citations are shown on each study's BioTime page.

#### Column mapping

BioTime per-study CSVs use the following columns, which are mapped to Darwin Core:

- valid_name: -> scientificName

- LATITUDE: -> decimalLatitude

- LONGITUDE: -> decimalLongitude

- ABUNDANCE: -> organismQuantity; organismQuantityType set to "abundance"

- BIOMAS: -> biotime_biomass (non-DwC passthrough; note the one-s spelling in BioTime source files)

- DAY, MONTH, YEAR: -> day, month, year

- SAMPLE_DESC: -> eventID (BioTime sample identifier)

occurrenceStatus is set to "present" when ABUNDANCE > 0 or BIOMAS > 0; "absent" when at least one of the two is a valid, explicit zero; and NA when neither ABUNDANCE nor BIOMAS parses to a number at all (missing or malformed in the source CSV) -- an unparseable value is not treated as a confirmed non-detection. Explicit zero records are retained; filter with dplyr::filter(occurrenceStatus == "present") if absences (and unknowns) are not needed.

### report_fetch(occurrences, study_area = NULL, verbose = FALSE)

Generate a Report Section for Data Acquisition

Summarizes the occurrence data fetched by TaxaFetch into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrences | yes |  | Data frame. Stacked occurrence records, typically the output of stack_occurrences. Must contain at least scientificName. Optionally contains bibliographicCitation, decimalLatitude, decimalLongitude, year, datasetID. |
| study_area | no | NULL | Character or NULL. Plain-language description of the study area (e.g. "Southern California coast"). If NULL, the geographic extent is described from coordinate ranges. |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object (S3 class from TaxaTools) with: methods Template text describing data sources and scope. results Template text summarizing record counts. citations Unique values from 'bibliographicCitation' column. params Named list of acquisition parameters (bbox, year_range). statistics Named list of summary counts.

### screen_eml_columns(ids, bbox, pause_seconds = 0.5, verbose = TRUE)

Pre-Screen DataONE Candidates via EML Metadata

For each candidate dataset ID (typically the output of 'parse_geo_screening_response'), fetches the EML metadata document and checks two things:

| Param | Required | Default | Doc |
|---|---|---|---|
| ids | yes |  | Character vector of PASTA dataset IDs to screen (e.g. "knb-lter-sbc.17.18" or "edi.123.4"). |
| bbox | yes |  | Numeric vector of the query bounding-box coordinates, in the order c(west, east, south, north) (decimal degrees, WGS84). |
| pause_seconds | no | 0.5 | Numeric. Pause between EML requests. Default 0.5. |
| verbose | no | TRUE | Logical. Print per-dataset progress. Default TRUE. |

**Value:** A tibble with one row per input ID and columns: id Original dataset ID as supplied (2-part, e.g. '"edi.1835"'). Use this column to join back to 'accepted'. resolved_id Fully-qualified 3-part PASTA ID (e.g. '"edi.1835.3"'). Use this column when calling 'fetch_dataone_eml' or 'fetch_dataone_occurrences' directly. eml_bbox_ok Logical. 'TRUE' = EML bbox overlaps query; 'NA' = no bbox in EML (dataset retained); 'FALSE' = bbox confirmed outside query. has_lat Logical. A likely latitude column was found in the data tables. has_lon Logical. A likely longitude column was found in the data tables. has_coords Logical. 'TRUE' if the dataset has usable coordinates by EITHER route: a detected 'lat_col' AND 'lon_col' pair, OR at least one EML point site ('has_eml_sites'). This is the column 'eml_status'/ 'eml_pass' actually key off; 'has_lat'/'has_lon' alone are not sufficient on their own since a dataset with EML point sites can have usable coordinates with both 'FALSE'. has_species Logical. A likely species/taxon column was found. has_eml_sites Logical. At least one EML point site was found in '<geographicCoverage>' (bounding box where west==east and north==south). Datasets with EML point sites pass coordinate screening even when 'has_lat' and 'has_lon' are 'FALSE' - Pass 5 of 'fetch_dataone_occurrences' will inject the coordinates. lat_col Character. Detected latitude column name, or 'NA'. lon_col Character. Detected longitude column name, or 'NA'. species_col Character. Detected species column name, or 'NA'. n_tables Integer. Number of EML '<dataTable>' elements - the EML element type describing one rectangular data file within the dataset (a dataset package can bundle more than one data table). eml_status Character. One of '"pass"', '"fetch_failed"', '"no_bbox_overlap"', '"no_coords"' (no lat/lon columns AND no EML point sites), '"no_species"', '"no_eml_bbox"'. eml_pass Logical. 'TRUE' if 'eml_status == "pass"' or '"no_eml_bbox"' and coordinates + species columns detected. Use this column to filter before downloading.

#### Details

This is the step between geographic LLM screening and the expensive data-file download in fetch_dataone_occurrences.

Column detection uses case-insensitive pattern matching against the EML <attributeName> values across all <dataTable> elements. Patterns:

- Latitude: lat, latitude, decimallatitude, y_coord, northing, yloc

- Longitude: lon, long, longitude, decimallongitude, x_coord, easting, xloc

- Species: species, taxon, scientific, organism, genus, sp_name, common_name, accepted_name, vernacular

Bbox note: Many EML documents lack <boundingCoordinates> even when the data are geographically specific. These are flagged eml_bbox_ok = NA and retained if column detection passes -- the record-level filter in fetch_dataone_occurrences will handle the final spatial check.

### screen_pdf_structure(pdf_content, use_llm = TRUE, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), model = "claude-sonnet-4-6", max_tokens = 400L, api_key = Sys.getenv("ANTHROPIC_API_KEY"), verbose = TRUE)

Characterize a PDF Paper on Five Axes for Occurrence Extraction

Stage 2 of the PDF occurrence pipeline. Reads section texts from a 'extract_pdf_text' output object, classifies the paper on five axes that control how Stage 3 extraction is configured, builds a page-level table indicating which pages should be sent as images, and constructs an inventory of Latin binomial abbreviations for use in the extraction prompt.

| Param | Required | Default | Doc |
|---|---|---|---|
| pdf_content | yes |  | A named list as returned by extract_pdf_text. Must contain elements $sections, $page_map, $n_pages, and $has_headers. |
| use_llm | no | TRUE | Logical. If TRUE (default), the five axis classifications are obtained from an LLM API call. If FALSE, all five axes are set to NA and a warning is issued that results will be less reliable. Heuristic classification is not yet implemented; use_llm = FALSE is provided for testing and batch triage only. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Function. The LLM call function to use. Must accept a single character string (the prompt) as its first argument and return a single character string (the response). Default call_anthropic_api. To use a different provider, pass a compatible wrapper function: my_openai <- function(prompt_str, ...) { # ... call OpenAI API ... return(response_text) } screen_pdf_structure(pdf_content, llm_fn = my_openai) |
| model | no | "claude-sonnet-4-6" | Character. Model identifier passed to llm_fn. Default "claude-sonnet-4-6" (cheaper than opus; sufficient for structured classification). |
| max_tokens | no | 400L | Integer. Maximum response tokens for the LLM call. Default 400L (JSON response is short). |
| api_key | no | Sys.getenv("ANTHROPIC_API_KEY") | Character. API key passed to llm_fn when using the default call_anthropic_api. Reads from the ANTHROPIC_API_KEY environment variable. Ignored when a custom llm_fn is supplied. |
| verbose | no | TRUE | Logical. Report progress. Default TRUE. |

**Value:** An S3 object of class 'c("pdf_structure", "list")' with elements: observation_type Character. One of: '"field_survey"', '"compilation_review"', '"experimental_lab"', '"monitoring_time_series"', '"prevalence_abundance"'. 'NA' if classification failed. location_structure Character. One of: '"explicit_latlon"', '"named_localities"', '"split_tables"', '"single_site"'. 'NA' if classification failed. data_density Character. One of: '"tabular"', '"prose_dense"', '"prose_sparse"', '"supplementary"'. 'NA' if classification failed. taxonomic_scope Character. One of: '"single_species"', '"few_species"', '"community_survey"'. 'NA' if classification failed. contamination_risk Character. One of: '"high"', '"low"'. 'NA' if classification failed. page_table Data frame with columns 'page' (integer), 'section' (character), 'content_type' (character: '"prose"', '"table"', '"figure"', '"mixed"', '"other"'), 'legend_text' (character, 'NA' if none), 'send_image' (logical). abbreviation_inventory Named character vector. Names are abbreviated binomials (e.g. '"E. newberryi"'); values are the corresponding full binomials (e.g. '"Eucyclogobius newberryi"'). Zero-length if none detected. has_supplementary Logical. 'TRUE' if the document contains an appendix or supplementary section. single_site_rule Logical. 'TRUE' if 'location_structure == "single_site"', meaning Stage 3 should inject a single set of coordinates for all extracted records rather than expecting per-record locality fields.

#### Details

No PDF page images are sent in this stage. The LLM call (if enabled) receives only plain text (abstract + methods + results), keeping token cost low.

Extraction decisions driven by axis values:

- observation_type == "experimental_lab" or "prevalence_abundance" -> consider skipping extraction entirely (no DwC occurrence records expected).

- data_density == "tabular" -> Stage 3 should prioritise table pages (send_image = TRUE rows where content_type == "table").

- data_density == "prose_dense" -> Stage 3 must read narrative text pages as images (species account style, like Swift et al. 1993).

- contamination_risk == "high" -> extraction prompt should explicitly instruct the model to skip Introduction and Discussion species mentions.

- single_site_rule == TRUE -> extraction prompt should note the single study site and inject its coordinates.

Page table and send_image logic: Pages in discussion, acknowledgements, funding, and references sections are always send_image = FALSE. Figure pages are scored by legend keyword matching against an occurrence vocabulary; figures without occurrence-relevant legends are skipped. Table pages in core sections are always sent. Appendix pages are sent only when has_supplementary = TRUE.

No LLM fallback: When use_llm = FALSE, all five axis values are NA. There is no heuristic classifier. This mode is intended for pipeline testing and batch triage where cost must be minimised and imprecise characterization is acceptable.

Provider note: Only call_anthropic_api is provided as a built-in llm_fn. Support for additional providers (OpenAI, Ollama, etc.) is a planned future addition to llm_api_utils.R. In the meantime, any function matching the (prompt_str, model, max_tokens, api_key, ...) signature can be passed as llm_fn.

### search_dataone(bbox, keywords = NULL, max_rows = 500L, exclude_noise = TRUE, min_bio_score = 1L, verbose = TRUE)

Discover Occurrence-Bearing Datasets from EDI / PASTA

Queries the EDI PASTA+ Solr index for all datasets ('q=*:*'), then filters results in R by bounding-box overlap on the returned 'coordinates' field. An optional 'keywords' argument adds Solr 'fq' constraints on 'title', 'geographicdescription', and 'taxonomic' fields before the R-side bbox filter.

| Param | Required | Default | Doc |
|---|---|---|---|
| bbox | yes |  | Named list with numeric elements west, east, south, north (decimal degrees, WGS84). Datasets whose geographic coverage does not overlap this box are removed. Records with unparseable coordinates are retained (fail open). Pass NULL to skip spatial filtering and return all results. |
| keywords | no | NULL | Optional character vector. Simple search terms added as Solr fq filters (one OR-joined fq param, searching title, geographicdescription, and taxonomic). E.g. c("kelp", "fish", "invertebrate"). NULL (default) applies no keyword filter. |
| max_rows | no | 500L | Integer. Rows to fetch from Solr before R-side filtering. Default 500L. Increase for large bboxes. |
| exclude_noise | no | TRUE | Logical. Exclude the ecotrends and lter-landsat* scopes (~25 000 non-occurrence packages). Default TRUE. |
| min_bio_score | no | 1L | Integer. Minimum biological relevance score to flag is_candidate = TRUE. Default 1L. Set 0L for all. |
| verbose | no | TRUE | Logical. Print progress. On first run, set TRUE to see the raw coordinates value format returned by PASTA, which is needed to verify the bbox parser is working. Default TRUE. |

**Value:** A tibble sorted by 'bio_score' descending, with columns: 'id', 'title', 'scope', 'pubdate', 'geographicdescription', 'taxonomic', 'keywords_str', 'authors', 'begindate', 'enddate', 'abstract', 'coordinates_raw', 'bbox_status' (one of '"overlap"', '"no_overlap"', '"unparseable"', '"no_filter"'), 'bio_score', 'has_taxonomic', 'is_candidate'.

### search_literature(taxon_scope, geo_scope = NULL, bbox = NULL, api_key = Sys.getenv("OPENALEX_API_KEY"), max_results = 200L, from_year = NULL, open_access = TRUE, cache_dir = NULL, verbose = TRUE)

Search the OpenAlex literature catalog for occurrence-relevant papers

Queries the OpenAlex API for papers matching a taxon scope and geographic bounding box, and returns a catalog tibble with the same column structure as 'harvest_dataone_catalog'. This makes the entire downstream PDF pipeline (optional taxon screening -> optional geo screening -> structure characterisation -> extraction) reusable unchanged.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_scope | yes |  | Character string. Comma-separated taxon names or synonyms, e.g. "timema" or "gobies, goby, Gobiidae, tidewater goby, Eucyclogobius". Terms are OR-grouped: any term matching in title or abstract is sufficient. |
| geo_scope | no | NULL | Character string or NULL (default). Comma-separated place names describing the study area, e.g. "California, Arizona" or "Santa Barbara Channel, southern California". Terms are OR-grouped and AND-combined with taxon_scope. Set NULL to search without geographic pre-filtering. |
| bbox | no | NULL | Numeric vector of length 4: c(lon_min, lon_max, lat_min, lat_max). Stored as metadata on the result tibble for downstream reference only -- does not affect the search query. Pass NULL (default) if no bbox is relevant. |
| api_key | no | Sys.getenv("OPENALEX_API_KEY") | Character. OpenAlex API key. Defaults to Sys.getenv("OPENALEX_API_KEY"). |
| max_results | no | 200L | Integer. Maximum papers to return. Default 200L. Results are returned in OpenAlex relevance order. |
| from_year | no | NULL | Integer or NULL. Filter to papers published from this year onward. Default NULL. |
| open_access | no | TRUE | Logical. Restrict to open-access papers with a direct PDF URL. Default TRUE. |
| cache_dir | no | NULL | Character or NULL. Directory for .rds disk cache keyed by query hash. NULL (default) disables caching. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A tibble with columns: 'id', 'title', 'abstract', 'keywords', 'doi', 'pdf_url', 'year', 'authors', 'journal', 'geo_match' ('NA'), 'taxon_match' ('NA'). Returns 'invisible(NULL)' with a message if no results are found. Attributes: 'taxon_scope', 'geo_scope', 'bbox', 'query_date'.

### stack_occurrences(..., lat_col = "decimalLatitude", lon_col = "decimalLongitude")

Stack Multiple Occurrence Data Frames

Row-binds one or more occurrence data frames and adds a 'point_id' column constructed from the latitude and longitude columns. Checks that every input frame contains the required coordinate columns before binding, so a forgotten 'rename_cols' call is caught immediately rather than producing a frame full of 'NA' coordinates.

| Param | Required | Default | Doc |
|---|---|---|---|
| ... | yes |  | One or more data frames to combine, or a single named list of data frames (the pattern used in the PDF and DataONE workflow scripts, e.g. stack_occurrences(pdf_occ_list_clean)). When a single list is supplied its elements are used as the frames to combine. A single data frame is returned as-is with point_id added. |
| lat_col | no | "decimalLatitude" | Character. Name of the latitude column. Default "decimalLatitude". |
| lon_col | no | "decimalLongitude" | Character. Name of the longitude column. Default "decimalLongitude". |

**Value:** A single tibble containing all rows from every input frame with an additional 'point_id' column appended, formed by pasting 'lat_col' and 'lon_col' separated by '"_"'. No rows are removed - the row count is always the sum of the input frames' row counts.

#### Details

This function only combines and labels rows -- it does not remove, filter, or aggregate anything, including duplicate records. Call dedupe_occurrences afterward (or on a single, unstacked source -- deduplication is relevant even without combining anything, see that function's Details) to remove duplicate/redundant records.

Single-frame input: When only one data frame is supplied (or a list with one element), it is returned directly with point_id added and a message reporting the record count. This avoids errors when the upstream pipeline produced only one successful result.

List input: The workflow scripts pass a named list such as pdf_occ_list_clean directly. stack_occurrences detects this and unpacks the list automatically -- no need to call do.call(stack_occurrences, list) manually.

Column alignment: dplyr::bind_rows matches columns by name. Rename columns to a common convention with rename_cols before calling this function so that latitude, longitude, taxon name, and date columns align correctly across sources.

point_id: If a point_id column already exists in any input frame it will be overwritten in the combined output so that all rows use a consistent format.

### taxafetch_clear_cache(cache_dir = tools::R_user_dir("TaxaFetch", "cache"), older_than_days = NULL, orphans_only = FALSE, zips_only = FALSE, dry_run = FALSE, force = FALSE)

Report and clear TaxaFetch's on-disk cache

TaxaFetch caches GBIF download zips ('download_gbif_occurrences()'), checkpoint files ('fetch_gbif_occurrences()'), iNaturalist range polygons ('check_inat_range()'), and (if enabled) OpenAlex literature results ('search_literature()') under a persistent, user-level cache directory. None of these expire automatically - GBIF zips in particular are permanent until removed by hand. This function reports how much space the cache is using and, unless 'dry_run = TRUE', removes it.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character. Cache directory to inspect/clear. Defaults to tools::R_user_dir("TaxaFetch", "cache"), the same default used by download_gbif_occurrences()/fetch_gbif_occurrences()/ check_geographic_outliers(). |
| older_than_days | no | NULL | Numeric or NULL. When supplied, only files older than this many days (by modification time) are targeted. NULL (default) targets every recognized cache file in cache_dir. |
| orphans_only | no | FALSE | Logical. If TRUE, targets only GBIF download zips (and zip sidecars -- see below) that are no longer referenced by any current download_gbif_occurrences() metadata file in cache_dir -- i.e. zips superseded by a later overwrite = TRUE run. The zip each metadata file currently points to (its query's most recent cached download), every metadata file itself, every fetch_gbif_occurrences() checkpoint, and every iNaturalist range file are left untouched -- this is the "keep the most recent cache per query, remove only stale leftovers" mode. Default FALSE (target everything recognized). Since a metadata file only ever names X.zip, a X.zip.<suffix> sidecar -- a partial transfer, or a bad download renamed out of the way by hand -- is unreferenced by construction and is always targeted here. |
| zips_only | no | FALSE | Logical. If TRUE, targets only the downloaded GBIF .zip files and their sidecars, leaving every metadata file and .rds checkpoint in place. This is usually the setting you want for reclaiming space: the zips are the cache in practice (38 of them held 17 GB on one real machine, against 52 MB for every .rds combined), they are pure redundancy once imported, and keeping their metadata means a later identical call re-fetches the same prepared GBIF key with no new request or queue wait. Unlike orphans_only this includes zips still referenced by current metadata -- those are exactly the large ones. Cannot be combined with orphans_only. |
| dry_run | no | FALSE | Logical. If TRUE, reports what would be removed without removing anything. Default FALSE. |
| force | no | FALSE | Logical (default FALSE). Pass TRUE to clear a cache_dir that holds file(s) matching none of the recognized cache patterns -- see list_cache_files. |

**Value:** Invisibly, a data frame of the targeted files ('path', 'size_mb', 'mtime'), possibly zero rows.

## Quick Start

``` r
library(TaxaFetch)

# 1. Define a bounding box (Southern California coast)
bbox <- make_bbox_wkt(lat = 34.0, lon = -119.25, radius_deg = 0.5)

# 2. Get GBIF taxon keys from verified names, with full hierarchy context
#    to avoid homonym errors
hierarchy_df <- data.frame(
  genus   = c("Fundulus", "Atherinops"),
  species = c("Fundulus parvipinnis", "Atherinops affinis")
)
keys <- get_keys_from_context(hierarchy_df)

# 3. Fetch GBIF occurrences
gbif_data <- fetch_gbif_occurrences(keys = keys$usageKey, geometry = bbox)

# 4. Filter to high-quality records
filtered <- filter_gbif_quality(gbif_data, max_coord_uncertainty = 500)

# 5. Stack multiple sources into one table
all_data <- stack_occurrences(gbif = filtered)
```

