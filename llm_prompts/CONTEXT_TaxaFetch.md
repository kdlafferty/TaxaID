# CONTEXT: TaxaFetch

**Fetch and Prepare Taxonomic Occurrence Data**

Provides tools for acquiring, combining, and preparing taxonomic occurrence data from multiple sources including GBIF and DataONE. The user specifies a spatial area and taxonomic group; TaxaFetch retrieves occurrence records and aligns column naming to DarwinCore conventions. Habitat assignment and spatial quality control are handled by TaxaHabitat. Output is a data frame of taxonomic occurrences at various locations and times. These data feed into TaxaHabitat and then TaxaExpect, which generates spatially explicit predictions of relative occurrence across taxa. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-20 21:09:26 UTC; unix). 32 exported function(s).

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

**Value:** An object of classes 'c("geo_prompt", "llm_prompt")', a named list with elements: prompts List of prompt strings, one per chunk. chunks List of character vectors of descriptions, one per chunk. n_chunks Integer. n_items Integer. Number of unique descriptions sent to the LLM. descriptions Character vector. All unique descriptions submitted (in order matching the LLM index column). desc_to_ids Named

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

**Value:** An S3 object of class 'c("pdf_extract_prompt", "llm_prompt")' with elements: • '$prompts' - character vector of prompt strings (length 1 normally; '>1' when 'chunk_pages = TRUE' and 'n_send > 25') • '$page_chunks' - list of integer vectors, one per prompt, giving the page numbers for each chunk • '$n_chunks' - integer; number of chunks • '$n_send' - integer; total pages flagged for sending • '$dpi

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

**Value:** An object of classes 'c("taxon_prompt", "llm_prompt")', a named list with elements: prompts List of prompt strings, one per chunk. chunks List of character vectors of dataset IDs, one per chunk. n_chunks Integer. n_items Integer. Number of datasets submitted to the LLM. ids Character vector. All dataset IDs submitted (in order matching the LLM index column). skipped_ids Character vector. Dataset I

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

### check_geographic_outliers(local_occurrences, min_local_n = 5L, min_occs = 7L, method = "distance", tdi = 1000, mltpl = 5, year_range = .gbif_default_year_range(), cache_dir = tools::R_user_dir("TaxaFetch", "cache"), candidate_taxa = NULL, candidate_scope = c("genus", "species", "all"), verdict_cache = TRUE, verbose = FALSE)

Flag Geographically Isolated Occurrence Records Against a Species' Global Range

A bbox-scoped GBIF search (see 'get_gbif_occurrences') can return a single occurrence for a species that is genuinely absent from the study region - a misidentification, mislabeled specimen, or bad georeference elsewhere in GBIF, sitting far from that species' real range. This function targets exactly that case: for species with few local records, it fetches that species' unrestricted global GBIF occurrences ('geometry = NULL', see 'fetch_gbif_occurrences') and tests whether the local record(s) are geographic outliers against that global cloud, via 'CoordinateCleaner::cc_outl()'. Species with 

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
| candidate_taxa | no | NULL | Optional character vector of taxa that can actually be ASSIGNED -- typically the species-level match candidates (e.g. unique(match_obj$taxon_name)). NULL (default) preserves the pre-2026-09-05 behaviour of checking every locally-rare species in the pool. Supplying it is strongly recommended for a family-derived occurrence pool: at real PtConception 18S only 387 of 7,392 pool species (5.2%) were match candidates, so 95% of the per-species GBIF requests protected against a harm those species cannot cause. A species with 1-4 local records has a theta far below TaxaAssign::join_priors()'s expansion_min_prior, so it can never be expanded into a hypothesis; its only residual effect is +1 to the Good-Turing f1. A locally-rare MATCH CANDIDATE is the opposite: its prior multiplies its likelihood directly, which is the misidentified-record failure this check exists for. |
| candidate_scope | no | c("genus", "species", "all") | How candidate_taxa restricts the check. "genus" (default) keeps any locally-rare species sharing a genus with a candidate -- congeners matter because TaxaLikely::restore_suppressed_candidates() and expand_unreferenced_hypotheses() can promote one into a named hypothesis. "species" keeps only exact candidates (tightest). "all" ignores candidate_taxa entirely. Family scoping is deliberately not offered: an occurrence pool fetched from family keys already contains only candidate families, so it would restrict nothing. |
| verdict_cache | no | TRUE | Logical, default TRUE. Cache the per-record VERDICTS rather than the global occurrence cloud. The cloud is reduced to one integer per species and one logical per local record and then discarded, so caching it stores millions of records to preserve a few thousand numbers. The verdict file is keyed on the species set and the cc_outl() parameters, so changing either recomputes. |
| verbose | no | FALSE | Logical. Forwarded to cc_outl(). Default FALSE. |

**Value:** 'local_occurrences' with three columns added: 'local_n' Number of records for this species in 'local_occurrences'. 'global_n_unique' Number of geographically unique global records found for this species. 'NA' for species never checked ('local_n >= min_local_n'). 'outlier_status' One of '"not_tested_sufficient_local_data"' (local_n >= min_local_n, never checked), '"insufficient_global_data"' (check

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

**Value:** A tibble with columns 'taxon_name', 'taxon_id', 'matched_name', 'name_match' (does the resolved iNat name equal the query, case-insensitively - FALSE flags a fuzzy-match resolution to a DIFFERENT taxon, which must never drive a prior elevation), 'rank', 'iconic_taxon_name', 'inat_kingdom', 'n_observations', 'in_range', 'range_status'. 'inat_kingdom' is derived from 'iconic_taxon_name' via a fixed 

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
| on_submit_failure | no | c("use_cache", "error") | "use_cache" (default) or "error". What to do when every submission attempt -- or every attempt to fetch the prepared file (curl timeouts, resets, truncated transfers) -- fails AND a verified cached zip for this exact query exists (only possible with overwrite = TRUE, since the default already reuses such a zip without asking GBIF at all). "use_cache" imports that zip with a loud warning() naming the failure, the cache date and the download key, and sets attr(result, "served_from_cache_after_failure") = TRUE; the cached zip is kept as the live cache. "error" fails as before. With no usable cached zip the function always errors. |
| prompt_mb | no | 50 | Numeric. In an INTERACTIVE session, a prepared download at least this many MB triggers a summary (size, record count, whether a zip for this exact query is already cached, what the cache holds now and will hold afterwards) and a choice: use the cache, download and replace it, or abort to narrow the query first. Smaller downloads proceed silently, and a NON-interactive session never blocks -- it reports the same facts and continues. Default 50; Inf disables the prompt entirely. The summary is placed before any bytes are transferred, because GBIF reports a prepared download's size and record count at that point, which is the only moment the information can still change the decision. |
| cache_prompt_mb | no | 5120 | Numeric. After a run, if the cache directory exceeds this many MB, an interactive session is offered a choice to free space (leave it; remove OTHER downloads but keep this query's zip; remove everything). A non-interactive session only reports. Default 5120 (5 GB); Inf disables the prompt while keeping the size report. |
| allow_prompts | no | FALSE | Logical, default FALSE. Whether this function may BLOCK on an interactive utils::menu(). Off by default because a blocking prompt inside a function that is called from a script is unsafe: when RStudio runs or sources a script it queues the remaining lines as console input, and menu() consumes those lines as answers -- re-prompting on each one, and, far worse, SILENTLY SWALLOWING them so they never execute. This package already documents the same hazard for readline() in TaxaMatch::group_observations_by_bbox(); there the advice is "run this call on its own", which is not available to a function called mid-workflow. With FALSE every decision is REPORTED with the exact command to act on it, and nothing blocks. Set TRUE only when calling this function by hand at the console. |
| keep_zip | no | TRUE | Logical, default TRUE. Whether to retain the downloaded zip in cache_dir after a successful import. The zip is pure redundancy once imported -- its only value is avoiding a re-download -- and it is by far the largest thing this package writes: on one real machine 38 zips accounted for 17 GB of a 17.05 GB cache, while every .rds checkpoint together came to 52 MB. With FALSE the zip is deleted after import and the small metadata file is KEPT, so a later identical call re-fetches the SAME prepared GBIF key -- no new request, no queue wait, just the transfer. Set FALSE when the caller persists the imported data itself (every workflow in this ecosystem saves a _raw_gbif.rds checkpoint, which makes the zip doubly redundant). |
| status_ping | no | 15 | Numeric. Seconds between download-status polls while waiting for GBIF to prepare the file. Default 15. Minimum enforced by rgbif is 3. |
| exclude_absent | no | TRUE | Logical. When TRUE (default), adds a server-side occurrenceStatus = PRESENT predicate, excluding explicit absence records before the file is built by GBIF. Systematic surveys (e.g., eBird, iNaturalist) can contribute large numbers of ABSENT rows that inflate the download size without providing presence data. Set to FALSE only if you need absence records. Changing this parameter changes the cache key and triggers a fresh download. |
| basis_keep | no | NULL | Character vector or NULL. When not NULL, adds a server-side basisOfRecord predicate to the GBIF download request, reducing the size of the downloaded zip. Only occurrence records with a basisOfRecord value in this vector are included. Typical values: "HUMAN_OBSERVATION", "MACHINE_OBSERVATION", "LIVING_SPECIMEN", "PRESERVED_SPECIMEN", "MATERIAL_SAMPLE". NULL (default) requests all basis types. Changing this parameter changes the cache key and triggers a fresh download. For eDNA projects where you want only field observations, use c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION"). |
| select_cols | no | c("kingdom", "phylum", "class", "order", "family", "genus", "species",      "infraspecificEpithet", "taxonRank", "scientificName", "taxonKey",      "speciesKey", "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",      "countryCode", "stateProvince", "year", "month", "day", "basisOfRecord",      "issue", "occurrenceStatus", "samplingProtocol", "occurrenceRemarks",      "preparations", "gbifID", "datasetKey", "license") | Character vector or NULL. Columns to retain after import. Uses data.table::fread's select argument so only the named columns are read into memory, which is much faster for large files. Does not reduce the downloaded zip size; use basis_keep for that. NULL loads all columns. The default is a set of ~35 columns covering the full TaxaID pipeline (taxonomy, spatial, temporal, quality, eDNA filter, and backbone keys). Unrecognised column names are silently ignored. |
| gbif_user | no | Sys.getenv("GBIF_USER") | Character. GBIF username. Defaults to the GBIF_USER environment variable; see Details for setup. |
| gbif_pwd | no | Sys.getenv("GBIF_PWD") | Character. GBIF password. Defaults to the GBIF_PWD environment variable. |
| gbif_email | no | Sys.getenv("GBIF_EMAIL") | Character. GBIF registered email address. Defaults to the GBIF_EMAIL environment variable. |
| beep | no | FALSE | Logical. If TRUE and the beepr package is available, plays a sound on completion. Falls back to a system bell character if beepr is absent. Default FALSE. |

**Value:** A tibble of occurrence records. Column structure matches 'fetch_gbif_occurrences' for downstream compatibility with 'filter_gbif_quality' and 'stack_occurrences'. The 'bibliographicCitation' column contains the GBIF download DOI (or the download key if DOI lookup fails). A 'download_key' attribute stores the GBIF download key for citation purposes.

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

**Value:** A named list with elements: sections Named list of character strings, one per requested section. Each string is the concatenated text of all pages in that section. Sections not detected in the document are absent. page_map Named list mapping section labels to integer vectors of page numbers (1-based). has_headers Logical. TRUE if section headers were detected. FALSE means the document has no expli

### fetch_dataone_eml(dataset_id)

Fetch Raw EML XML for an EDI / PASTA Dataset

Fetch Raw EML XML for an EDI / PASTA Dataset

| Param | Required | Default | Doc |
|---|---|---|---|
| dataset_id | yes |  | Character. PASTA package ID, e.g. "knb-lter-sbc.17.18". |

**Value:** Length-1 character string of raw EML XML.

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

**Value:** A tibble with standardized Darwin Core columns, or 'NULL' invisibly if no records survive all filters. Column order: 'occurrenceID', 'datasetID', 'datasetName', 'institutionCode', 'basisOfRecord', 'eventDate', 'year', 'month', 'day', 'decimalLatitude', 'decimalLongitude', 'coordinateUncertaintyInMeters', 'scientificName', 'genus', 'family', 'specificEpithet', 'vernacularName', 'individualCount', '

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

### fetch_inat_occurrences(taxon_names, lat, lng, radius_km = 50, captive = c("any", "true", "false"), quality_grade = c("any", "casual", "needs_id", "research"), api_token = Sys.getenv("INAT_API_TOKEN"), verbose = FALSE)

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
| verbose | no | FALSE | Logical. If TRUE, prints progress for each taxon. Default FALSE. |

**Value:** A tibble with columns 'taxon_name', 'taxon_id', 'matched_name', 'inat_kingdom' (derived from iNaturalist's own 'iconic_taxon_name' via the same fixed lookup 'check_inat_range' uses - compare against your own candidate's kingdom before trusting a result: iNaturalist resolves names against its own curated taxonomy, not NCBI's or GBIF's, so a name that matches an unrelated homonym in a different king

### fetch_occurrences_by_taxon(taxon_geometry_map, year_range = .gbif_default_year_range(), limit = NULL, combine_shared_geometry = TRUE, ...)

Fetch GBIF Occurrences Grouped by Taxon Key

Given a fetch scope expressed as one row per (site, candidate taxon) pair, unions the search geometry for each distinct taxon key and issues exactly one 'get_gbif_occurrences' call per taxon key (or per group of taxon keys that end up sharing an identical unioned geometry - see 'combine_shared_geometry'). This avoids two problems that arise when occurrence fetches are instead grouped by observation/site: (1) the same GBIF record can be counted twice if two separately-issued queries for the same taxon have overlapping search geometry, and (2) unrelated round trips are issued when several taxa s

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_geometry_map | yes |  | A data frame with (at least) columns taxon_key (integer or numeric GBIF usage key) and geometry (character, one WKT polygon per row -- see make_bbox_wkt / define_search_polygon). One row per (site, candidate taxon) pair: the same taxon_key may appear in multiple rows (different sites where that taxon is a genuine candidate), and the same geometry may appear for multiple taxon_key values (several taxa considered over the same search area). Rows with NA/empty taxon_key or geometry are dropped; exact duplicate rows are dropped before unioning. |
| year_range | no | .gbif_default_year_range() | Forwarded to get_gbif_occurrences. year_range defaults to "2000" through the current year, computed at call time. |
| limit | no | NULL | Forwarded to get_gbif_occurrences. year_range defaults to "2000" through the current year, computed at call time. |
| combine_shared_geometry | no | TRUE | Logical. Default TRUE. After unioning each taxon key's own geometry, taxon keys whose resulting unioned geometry is identical are combined into a single multi-key call -- different taxa over the same search area is a clean win to combine (no wasted download volume either way, just one fewer round trip). Set FALSE to always issue one call per taxon key. |
| ... | yes |  | Forwarded to get_gbif_occurrences (e.g. key_threshold, rank_filter, columns, cache_dir, overwrite, exclude_absent, basis_keep). |

**Value:** A tibble, same schema as 'get_gbif_occurrences' (records from every issued query, row-bound).

### filter_gbif_quality(data, basis_keep = c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION", "LIVING_SPECIMEN",      "PRESERVED_SPECIMEN"), exclude_edna = TRUE, exclude_absent = TRUE, bad_issues = c("COORDINATE_OUT_OF_RANGE", "COUNTRY_COORDINATE_MISMATCH", "COORDINATE_INVALID",      "ZERO_COORDINATE", "COORDINATE_PRECISION_INVALID"), max_coord_uncertainty = 500, max_coord_decimal_places = NULL, require_species = FALSE, exclude_equal_coords = TRUE, exclude_near_zero = TRUE, near_zero_buffer_m = 5000, exclude_near_gbif_hq = TRUE, exclude_country_centroid = TRUE, exclude_capital = TRUE, flag_institution = TRUE)

Filter GBIF Occurrence Records by Quality

Removes low-quality rows from a raw GBIF occurrence download. Applies up to twelve sequential filters: coordinate completeness, absent occurrences, basis of record, geospatial issue codes, coordinate uncertainty, coordinate decimal-place precision, eDNA/metabarcoding keyword removal, species-level requirement, and six 'CoordinateCleaner'-backed checks (identical lat/lon, near-zero coordinates, near GBIF headquarters, near a country/province centroid, near a national capital, near a biodiversity institution). Each filter is applied only when the relevant column (or package) is present; absent c

| Param | Required | Default | Doc |
|---|---|---|---|
| data | yes |  | A data frame of GBIF occurrence records. Must contain decimalLatitude and decimalLongitude. |
| basis_keep | no | c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION", "LIVING_SPECIMEN",      "PRESERVED_SPECIMEN") | Character vector. Values of basisOfRecord to retain. Records not in this vector are removed. Default retains human and machine observations and specimen records; excludes fossil and unknown sources. |
| exclude_edna | no | TRUE | Logical. If TRUE (default), records whose samplingProtocol, occurrenceRemarks, or preparations columns contain eDNA or metabarcoding keywords are removed. Set to FALSE if your workflow specifically targets eDNA data. |
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

**Value:** The input data frame with low-quality rows removed. Column structure is unchanged. A summary message reports the number of records retained. Every removed record is also preserved, not just counted: 'attr(result, "removed_records")' is a data frame with the same columns as the input plus 'filter_reason', one row per removed record (always present, possibly zero rows - never 'NULL', so it can be in

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

### get_keys_from_context(hierarchy_df)

Fetch GBIF Taxon Keys Using Full Taxonomic Context

Resolves a dataframe of scientific names to GBIF usage keys by supplying the full taxonomic hierarchy (kingdom, phylum, class, etc.) as context to the GBIF name backbone API. Providing hierarchy context prevents homonym errors where identical names refer to different organisms in different kingdoms.

| Param | Required | Default | Doc |
|---|---|---|---|
| hierarchy_df | yes |  | A dataframe. Each row is one taxon. Columns should be named for Linnaean ranks (case-insensitive): kingdom, phylum, class, order, family, genus, species. Not all ranks need to be present. For each row, the most specific rank provided is used as the lookup target; higher ranks are passed as disambiguation context. |

**Value:** The input dataframe with three columns appended: usageKey Integer. GBIF usage key for the matched name, or 'NA' if no match was found. matchType Character. GBIF match quality: '"EXACT"', '"FUZZY"', '"HIGHERRANK"', '"LOOKUP_RECOVERED"' (a '"HIGHERRANK"' result recovered via a secondary 'name_lookup()' call - see '@details'), '"NONE"', '"NO_DATA"' (no rank columns present in this row), or '"ERROR"' 

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

### make_bbox_wkt(lat, lon, radius_deg)

Create a WKT Bounding Box Around a Central Point

Generates a Well-Known Text (WKT) POLYGON string representing a square bounding box centred on a given latitude and longitude. The result is ready to pass directly to the 'geometry' argument of 'fetch_gbif_occurrences'.

| Param | Required | Default | Doc |
|---|---|---|---|
| lat | yes |  | Numeric. Latitude of the centre point in decimal degrees (WGS 84). Must be in the range [-90, 90]. |
| lon | yes |  | Numeric. Longitude of the centre point in decimal degrees (WGS 84). Must be in the range [-180, 180]. |
| radius_deg | yes |  | Numeric. Half-width of the bounding box in decimal degrees. The box extends radius_deg degrees in each direction from the centre, giving a total side length of 2 * radius_deg -- a square in degree-space, not in physical distance. Must be positive. For reference: 1 degree of latitude is approximately 111 km at any latitude; 0.5 degrees is approximately 55 km. This conversion holds only along the north-south axis. East-west, 1 degree of longitude shrinks by a factor of cos(latitude) (e.g. only about 78 km at 45 degrees latitude, about 39 km at 70 degrees), so the box's true east-west coverage is narrower than its north-south coverage away from the equator -- a real consideration for high- latitude sites. |

**Value:** A length-1 character vector: a WKT POLYGON string with vertices ordered counter-clockwise and the first and last vertex identical (closed ring), as required by the GBIF occurrence API.

### parse_geo_screening_response(raw_text, geo_prompt)

Parse an LLM Geographic Screening Response

Parses the raw text returned by an LLM in response to a 'build_geo_prompt' prompt, fans YES/NO decisions back to all datasets sharing each description, and returns a filtered tibble of candidate datasets.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character. Length-1 string containing the LLM response (from prompt_api or read_llm_response). |
| geo_prompt | yes |  | A geo_prompt object from build_geo_prompt. |

**Value:** A tibble with all columns from the input catalog plus: geo_match Logical. 'TRUE' = LLM said YES (or shortcut accepted); 'FALSE' = LLM said NO (or shortcut rejected). geo_source Character. One of '"llm_yes"', '"llm_no"', '"shortcut_accepted"', '"shortcut_rejected"', '"no_description"', '"llm_no_response"'. The tibble includes ALL candidate packages - filter on 'geo_match == TRUE' to obtain the cand

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

**Value:** A tibble with all columns from the input catalog plus: taxon_match Logical. 'TRUE' = LLM said YES for taxon; 'FALSE' = LLM said NO or no response received. taxon_source Character. One of '"llm_yes"', '"llm_no"', '"skipped"' (no metadata available), '"llm_no_response"' (index missing from LLM output). geo_match Logical. Only present when 'taxon_prompt' was built with a 'geo_scope' argument. 'TRUE' 

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

**Value:** A tibble of class 'c("dataone_preview", "tbl_df", "tbl", "data.frame")' with one row per entity (or joinable pair) and columns: dataset_id PASTA identifier, e.g. '"edi.653.8"'. dataset_title Full dataset title (not truncated). entity_name Entity (table) name; for joinable pairs formatted as '"entity_A + entity_B"'. status One of '"ready"', '"large"', '"skip"', '"join_ready"', or '"join_large"'. Th

### read_biotime_study(local_path = NULL, study_id = NULL, verbose = TRUE)

Read and DwC-map a downloaded BioTime study CSV

Reads a single-study occurrence CSV downloaded from the BioTime database and returns a Darwin Core-mapped tibble compatible with 'stack_occurrences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| local_path | no | NULL | Character scalar or NULL. Path to the downloaded BioTime study CSV. If NULL (the default), a system file-chooser dialog is opened so you can navigate to the file interactively. Passing a path directly is recommended for reproducible scripts. |
| study_id | no | NULL | Character or integer scalar or NULL. The BioTime STUDY_ID for this file (e.g. 595L or "595"). Used to populate the datasetID column as "biotime:<study_id>". If NULL, the numeric portion of the filename is used when the filename matches the pattern raw_data_<id>.csv; otherwise datasetID is set to "biotime:unknown" with a warning. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A tibble with Darwin Core columns plus BioTime-specific passthroughs, compatible with 'stack_occurrences()': 'scientificName' Character. From 'valid_name'. 'decimalLatitude' Numeric. 'decimalLongitude' Numeric. 'year' Integer. 'month' Integer or NA. 'day' Integer or NA. 'occurrenceStatus' Character. '"present"', '"absent"', or 'NA' (neither 'ABUNDANCE' nor 'BIOMAS' parsed to a number for this row)

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

**Value:** A tibble with one row per input ID and columns: id Original dataset ID as supplied (2-part, e.g. '"edi.1835"'). Use this column to join back to 'accepted'. resolved_id Fully-qualified 3-part PASTA ID (e.g. '"edi.1835.3"'). Use this column when calling 'fetch_dataone_eml' or 'fetch_dataone_occurrences' directly. eml_bbox_ok Logical. 'TRUE' = EML bbox overlaps query; 'NA' = no bbox in EML (dataset r

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

**Value:** An S3 object of class 'c("pdf_structure", "list")' with elements: observation_type Character. One of: '"field_survey"', '"compilation_review"', '"experimental_lab"', '"monitoring_time_series"', '"prevalence_abundance"'. 'NA' if classification failed. location_structure Character. One of: '"explicit_latlon"', '"named_localities"', '"split_tables"', '"single_site"'. 'NA' if classification failed. da

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

### taxafetch_clear_cache(cache_dir = tools::R_user_dir("TaxaFetch", "cache"), older_than_days = NULL, orphans_only = FALSE, zips_only = FALSE, dry_run = FALSE)

Report and clear TaxaFetch's on-disk cache

TaxaFetch caches GBIF download zips ('download_gbif_occurrences()'), checkpoint files ('fetch_gbif_occurrences()'), iNaturalist range polygons ('check_inat_range()'), and (if enabled) OpenAlex literature results ('search_literature()') under a persistent, user-level cache directory. None of these expire automatically - GBIF zips in particular are permanent until removed by hand. This function reports how much space the cache is using and, unless 'dry_run = TRUE', removes it.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character. Cache directory to inspect/clear. Defaults to tools::R_user_dir("TaxaFetch", "cache"), the same default used by download_gbif_occurrences()/fetch_gbif_occurrences()/ check_geographic_outliers(). |
| older_than_days | no | NULL | Numeric or NULL. When supplied, only files older than this many days (by modification time) are targeted. NULL (default) targets every recognized cache file in cache_dir. |
| orphans_only | no | FALSE | Logical. If TRUE, targets only GBIF download zips (and zip sidecars -- see below) that are no longer referenced by any current download_gbif_occurrences() metadata file in cache_dir -- i.e. zips superseded by a later overwrite = TRUE run before this package's 2026-09-03 orphan-cleanup fix. The zip each metadata file currently points to (its query's most recent cached download), every metadata file itself, every fetch_gbif_occurrences() checkpoint, and every iNaturalist range file are left untouched -- this is the "keep the most recent cache per query, remove only stale leftovers" mode. Default FALSE (target everything recognized, the same as before this parameter existed). Since a metadata file only ever names X.zip, a X.zip.<suffix> sidecar -- a partial transfer, or a bad download renamed out of the way by hand -- is unreferenced by construction and is always targeted here. |
| zips_only | no | FALSE | Logical. If TRUE, targets only the downloaded GBIF .zip files and their sidecars, leaving every metadata file and .rds checkpoint in place. This is usually the setting you want for reclaiming space: the zips are the cache in practice (38 of them held 17 GB on one real machine, against 52 MB for every .rds combined), they are pure redundancy once imported, and keeping their metadata means a later identical call re-fetches the same prepared GBIF key with no new request or queue wait. Unlike orphans_only this includes zips still referenced by current metadata -- those are exactly the large ones. Cannot be combined with orphans_only. |
| dry_run | no | FALSE | Logical. If TRUE, reports what would be removed without removing anything. Default FALSE. |

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

