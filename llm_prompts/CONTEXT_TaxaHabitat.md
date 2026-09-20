# CONTEXT: TaxaHabitat

**Habitat Assignment and Spatial Quality Control for Taxonomic Occurrences**

Assigns habitat classifications to taxonomic occurrence records using LLM prompts and performs spatial quality control. Receives occurrence data from TaxaFetch and produces habitat-annotated, spatially screened records for input to TaxaExpect. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-20 21:06:03 UTC; unix). 18 exported function(s).

## Functions

### apply_spatial_review_decisions(occurrence_data, path, point_id_col = "point_id", flag_col = "spatial_flag", reason_col = "spatial_flag_reason", habitat_col = "main_habitat")

Apply saved spatial-flag decisions before (or instead of) the gadget

Overwrites 'spatial_flag' on every row whose 'point_id' has a saved decision (and 'main_habitat' where the decision was a reviewer reassignment), marks the reason, and reports how many flagged points still need a reviewer. Call it on 'flag_habitat_inconsistencies''s output; open 'review_spatial_flags' only when 'attr(result, "n_pending_review") > 0' (or when you deliberately want to re-review). A missing decisions file is not an error: nothing is applied and every flagged point is pending.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | Data frame from flag_habitat_inconsistencies (carries point_id, spatial_flag, spatial_flag_reason, main_habitat). |
| path | yes |  | Character. The decisions file written by save_spatial_review_decisions. |
| point_id_col | no | "point_id" | Column names. |
| flag_col | no | "spatial_flag" | Column names. |
| reason_col | no | "spatial_flag_reason" | Column names. |
| habitat_col | no | "main_habitat" | Column names. |

**Value:** 'occurrence_data' with decisions applied and attributes 'n_applied' (rows changed), 'n_pending_review' (distinct points whose flag is not '"likely"' and that carry no decision) and 'pending_point_ids'.

### assign_habitat_biological(occurrence_data, habitats_df, habitat_cols = NULL, point_id_col = "point_id", taxon_col = "taxon_name", weight_by_abundance = FALSE, threshold = 0.3, min_species_weight = 0)

Assign Habitat to Points Using Biological Consensus

Infers the habitat of each sampling point from the weighted habitat affinities of the species present there. Each species contributes its habitat weight vector (produced by 'parse_hierarchical_habitat_response') to a per-point sum; the habitat with the highest summed weight is assigned, provided it meets a minimum consensus threshold.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe of occurrence records. Must contain columns named by point_id_col and taxon_col. |
| habitats_df | yes |  | A dataframe giving habitat weights for each species. Must contain a column named by taxon_col, one numeric column per habitat in the scheme, and optionally Other_weight and habitat_best_guess. Produced by parse_hierarchical_habitat_response. |
| habitat_cols | no | NULL | Character vector naming the habitat weight columns in habitats_df. If NULL (default), all numeric columns other than taxon_col are used. Supply explicitly when the dataframe contains non-habitat numeric columns. "Other_weight" is always treated as a valid habitat column and propagated to main_habitat when it wins the consensus vote. |
| point_id_col | no | "point_id" | Character. Name of the point identifier column in occurrence_data. Default "point_id". |
| taxon_col | no | "taxon_name" | Character. Name of the taxon name column in both occurrence_data and habitats_df. Default "taxon_name". |
| weight_by_abundance | no | FALSE | Logical. If FALSE (default), each species contributes equally to the point score regardless of how many occurrence records it has at that point. If TRUE, species are weighted by their record count at the point, so abundant species have more influence. Default FALSE is recommended because record abundance in occurrence datasets is strongly influenced by sampling effort rather than true ecological dominance. |
| threshold | no | 0.3 | Numeric in (0, 1]. Minimum habitat weight fraction for a habitat to be classified as biologically relevant at a point. At 0.3, a habitat must receive at least 30% of the species-weighted votes to be assigned. Lower values include more marginal habitats; higher values restrict assignment to clearly dominant habitats. For transitional areas (e.g., estuaries), a lower threshold (0.2) may better capture mixed habitats. Default 0.3. Points where no habitat reaches the threshold receive main_habitat = "Uncertain" -- a named sentinel, not NA; see the main_habitat entry under Value. Note: the default is lower than in the single-habitat version because weight is now spread across multiple habitats per species; a threshold of 0.5 may be too strict for generalist communities. |
| min_species_weight | no | 0 | Numeric in [0, 1). Per-species weight floor. Any weight assigned to a habitat column by a species that is greater than zero but less than this value is set to zero before the consensus calculation. Default 0.0 (no floor, all weights used). Set to e.g. 0.1 to suppress LLM hedging weights -- small non-zero values the LLM assigns to vaguely plausible habitats that dilute the signal from the species' actual primary habitat(s). Has no effect when using the two-stage IUCN pipeline with the commit-at-confident-level prompt, which already discourages sub-0.1 weights by instruction. |

**Value:** The input 'occurrence_data' with four additional columns: main_habitat Character. The winning habitat label at each point, or '"Uncertain"' if no habitat reached 'threshold'. *Not 'NA'*: 'NA' in a 'main_habitat' column already means _habitat-agnostic, matches any habitat_ on the prior side, where 'TaxaExpect::generate_domestic_food_priors()' sets it deliberately and 'TaxaAssign::join_priors()' rea

### build_habitat_lookup(taxon_list, habitat_scheme = NULL, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), cache_dir = NULL, extra_covariates = character(0), chunk_size = 60L, geographic_context = NULL, cache_tag = "", pause_seconds = 1, verbose = TRUE)

Build a per-taxon habitat lookup with an on-disk cache

One call that does what the three-step pattern 'build_habitat_prompt()' -> 'TaxaTools::prompt_api()' -> 'parse_hierarchical_habitat_response()' does, but only asks the LLM about taxa it has not already classified under the same scheme. The result is the 'habitats_df' that 'assign_habitat_biological()' consumes.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_list | yes |  | Character vector of taxon names. |
| habitat_scheme | no | NULL | Passed to build_habitat_prompt(): NULL (the three-realm default), "IUCN_L1", or a scheme data frame. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Passed to TaxaTools::prompt_api(). Defaults to the TaxaID.llm_fn option, else TaxaTools::call_api. |
| cache_dir | no | NULL | Character or NULL (default). Directory for the per-taxon cache. NULL disables caching entirely (identical to the uncached three-step pattern). Workflows should pass a project-local directory, e.g. file.path(OUT_DIR, paste0(OUT_PREFIX, "_habitat_cache")). |
| extra_covariates | no | character(0) | Passed to build_habitat_prompt(). |
| chunk_size | no | 60L | Passed to build_habitat_prompt(). |
| geographic_context | no | NULL | Passed to build_habitat_prompt(). |
| cache_tag | no | "" | Character (default ""). Free-text component of the cache key; change it to force fresh verdicts (e.g. after a model change). |
| pause_seconds | no | 1 | Passed to TaxaTools::prompt_api(). |
| verbose | no | TRUE | Passed to TaxaTools::prompt_api(). |

**Value:** A data frame with one row per unique taxon in 'taxon_list' (the same shape 'parse_hierarchical_habitat_response()' returns), in 'taxon_list' order, with a 'cache_summary' attribute: 'n_total', 'n_from_cache', 'n_called', 'n_cached_new'.

### build_habitat_prompt(taxon_list, extra_covariates = character(0), chunk_size = 60L, habitat_scheme = NULL, geographic_context = NULL)

Build a Habitat Assignment Prompt

Creates a 'habitat_prompt' object containing one or more LLM prompt strings for habitat assignment. This is always Step 1 of the habitat assignment pipeline, regardless of which submission path is used in Step 2.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_list | yes |  | Character vector of scientific names. |
| extra_covariates | no | character(0) | Character vector of additional binary (0/1) covariate names to request from the LLM alongside habitat weights. Default character(0) (no extra covariates). Provide a character vector (e.g. c("Invasive", "Migratory")) only when you intend to use the trait information downstream; extra covariates add tokens and output columns that are ignored by the rest of the habitat pipeline. |
| chunk_size | no | 60L | Integer. Maximum taxa per prompt chunk. Default 60. Larger lists are split into multiple chunks automatically. Reduce if your LLM has a small context window; increase cautiously for APIs with large windows. |
| habitat_scheme | no | NULL | A dataframe defining the habitat classification to use, the string "IUCN_L1", or NULL. NULL (default) uses a simple three-category scheme: Marine, Freshwater, Terrestrial. This is always a valid starting point and is always interpretable in a model. "IUCN_L1" uses the 18 IUCN Level 1 group names as a single-level scheme. Pass a dataframe for a custom scheme (must contain l1_name; optional: l2_name, l2_code, realm). To generate a scheme automatically from the taxon list, use build_scheme_prompt + parse_scheme_response first, then pass the result here. See example_habitat_scheme for a dataframe template. |
| geographic_context | no | NULL | Optional character string describing the geographic region where these species were observed (e.g. "Southern California", "Chesapeake Bay watershed"). When non-NULL, the prompt includes a geographic context block and requests an additional ecoregion_best_guess column from the LLM. Default NULL (no geographic context). |

**Value:** An object of class 'c("habitat_prompt", "llm_prompt")', which is a named list: prompts List of character strings, one per chunk. taxa Character vector of deduplicated, trimmed taxon names. chunks List of character vectors, taxa per chunk. scheme The validated habitat scheme dataframe. habitat_cols Character vector of habitat column names the LLM will produce (the scheme's working habitat names, in

### build_iucn_scheme(realm = NULL, l1 = "all", l2 = "none")

Build a Habitat Scheme from the IUCN Red List Classification

Constructs a 'habitat_scheme' dataframe by subsetting the IUCN Red List Habitat Classification v3.1 to the realms, Level 1 groups, and Level 2 subcategories you specify. The result can be passed directly to 'build_habitat_prompt' as 'habitat_scheme'.

| Param | Required | Default | Doc |
|---|---|---|---|
| realm | no | NULL | Character or NULL. Filter to one ecological realm: "marine", "freshwater", "terrestrial", "artificial", or NULL (all realms, default). Realm groupings: "marine": Marine Neritic, Marine Oceanic, Marine Deep Ocean Floor, Marine Intertidal, Marine Coastal/Supratidal "freshwater": Wetlands (inland) "terrestrial": Forest, Savanna, Shrubland, Grassland, Rocky Areas (inland), Caves and Subterranean Habitats, Desert, Introduced Vegetation "artificial": Artificial - Terrestrial, Artificial - Aquatic "Other" and "Unknown" are excluded from all realm filters and must be requested explicitly via l1. |
| l1 | no | "all" | Character, "all", or "none". Which Level 1 groups to include in the scheme. "all" (default) includes all L1 groups in the selected realm as single-level categories. "none" excludes all L1 groups (only L2 subcategories will be present; requires l2 to be non-"none"). A character vector of L1 group names includes only those groups as fallback L1 columns alongside any L2 subcategories requested. Names are validated against the filtered lookup and a helpful error is given for unrecognised values. |
| l2 | no | "none" | Character, "all", or "none". Which Level 2 subcategories to include. "none" (default) produces a single-level scheme using only L1 group names. "all" adds all L2 subcategories under the selected L1 groups. A character vector of specific L2 names adds only those subcategories; their L1 parent groups are automatically added as fallback columns unless l1 = "none". Names are validated and an error lists the correct L1 parent for any unrecognised value. |

**Value:** A 'habitat_scheme' data.frame with columns 'l1_name', 'l2_name', 'l2_code', and 'realm', ready for 'build_habitat_prompt'. Rows with 'l2_name = NA' are L1-only entries (single-level fallback); rows with non-NA 'l2_name' are L2 entries. Print the result to inspect the scheme before use.

### build_scheme_prompt(taxon_list, min_habitats = 2L, max_habitats = 10L, realm = NULL)

Build a Habitat Scheme Generation Prompt

Asks an LLM to propose a compact, ecologically appropriate set of habitat categories for a given taxon list. The suggested scheme is then passed to 'build_habitat_prompt' as 'habitat_scheme', replacing the need for a user-supplied custom scheme or the full IUCN classification.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_list | yes |  | Character vector of scientific names. |
| min_habitats | no | 2L | Integer. Minimum number of habitat categories to generate. Default 2L. |
| max_habitats | no | 10L | Integer. Maximum number of habitat categories to generate. Default 10L. Reduce to force coarser resolution; increase if the LLM is merging ecologically distinct habitats. |
| realm | no | NULL | Character or NULL. Optional hint to constrain the scheme to a single ecological realm: "marine", "freshwater", or "terrestrial". Use when all taxa are known to belong to one realm and you want to prevent the LLM from generating irrelevant cross-realm categories. Default NULL (no constraint; the LLM infers realm from the taxon list). |

**Value:** An object of class 'c("scheme_prompt", "llm_prompt")' with elements: prompts List of length 1 containing the prompt string. taxa The deduplicated taxon list. chunks List of length 1. min_habitats The minimum supplied. max_habitats The maximum supplied. realm The realm hint supplied (or 'NULL'). n_chunks Always '1L'. n_items Number of taxa. Pass to 'prompt_api' or 'prompt_manual', then pass the raw

### consensus_habitat(habitats_df, habitat_cols = NULL, taxon_col = "taxon_name", threshold = 0.3)

Compute Assemblage-Level Consensus Habitat

Summarises per-species habitat weights into a single consensus habitat (and optionally ecoregion) for the entire assemblage. Each species contributes equally. Useful for inferring site-level habitat context from a list of candidate taxon names when occurrence records or spatial data are unavailable.

| Param | Required | Default | Doc |
|---|---|---|---|
| habitats_df | yes |  | A dataframe of per-species habitat weights, as produced by parse_hierarchical_habitat_response. Must contain a column named by taxon_col and one or more numeric habitat weight columns. |
| habitat_cols | no | NULL | Character vector naming the habitat weight columns. If NULL (default), auto-detected (all numeric columns except taxon_col and text columns). |
| taxon_col | no | "taxon_name" | Character. Name of the taxon name column. Default "taxon_name". |
| threshold | no | 0.3 | Numeric in (0, 1]. Minimum habitat weight fraction for a habitat to be classified as biologically relevant. At 0.3, a habitat must receive at least 30% of the species-weighted votes to be assigned. Lower values include more marginal habitats; higher values restrict assignment to clearly dominant habitats. For transitional areas (e.g., estuaries), a lower threshold (0.2) may better capture mixed habitats. Default 0.3. |

**Value:** A one-row data frame with columns: main_habitat Character. The consensus habitat, or 'NA' if none reached 'threshold'. *Deliberately 'NA', and deliberately unlike 'assign_habitat_biological'*, which returns the sentinel '"Uncertain"' for the same condition. See Details. ecoregion Character. The modal 'ecoregion_best_guess' value across species, or 'NA' if the column is absent. habitat_best_guess C

### drop_stale_seeded_decisions(occurrence_data, path, seeded_pattern = "^seeded from", dry_run = TRUE, backup = TRUE)

Drop Seeded Review Decisions That the Automatic Classifier Has Since Overtaken

A decision file seeded with 'before = NULL' records "accept the automatic classification" for every point, with 'decided_at' set to a '"seeded from ..."' string rather than a timestamp. Those are not reviewer judgements. When the automatic classifier later changes its mind about a point - because a bug was fixed, a habitat vocabulary was extended, or a threshold moved - the seeded verdict silently overrides the new one, and 'apply_spatial_review_decisions()' reports 'n_pending_review = 0'. The site then looks fully reviewed while carrying the old classifier's answer.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe freshly returned by flag_habitat_inconsistencies() -- i.e. carrying the CURRENT automatic spatial_flag, before any decisions are applied. |
| path | yes |  | Character. Path to the *_spatial_review_decisions.rds file. |
| seeded_pattern | no | "^seeded from" | Character regex identifying seeded rows by their decided_at value. Default "^seeded from", which is what save_spatial_review_decisions() writes. |
| dry_run | no | TRUE | Logical. When TRUE (default) nothing is written; the function reports what it would drop. Set FALSE to rewrite the file. |
| backup | no | TRUE | Logical. When writing, first copy the existing file to <path>.bak_<timestamp>. Default TRUE. |

**Value:** Invisibly, a list with 'n_decisions', 'n_seeded', 'n_real', 'n_stale', 'stale_point_ids' and 'path'. Called for its message output and, when 'dry_run = FALSE', its side effect.

### flag_habitat_inconsistencies(occurrence_data, lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", coast_buffer_m = 1000, marine_questionable_km = 0, depth_neritic_m = 200, depth_oceanic_m = 4000, resolution = 4L, verbose = TRUE, habitat_scheme = NULL)

Flag Spatially Inconsistent Habitat Assignments

For each unique occurrence point, derives the physical spatial zone (inland, coastal, marine shallow, marine deep, marine abyssal) using vector land polygons for land/ocean classification and NOAA bathymetry for ocean depth, then compares that zone against the species-based IUCN habitat assignment. Points whose physical location is implausible given their assigned habitat are flagged for user review.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe, typically occurrences_with_habitat from the TaxaExpect workflow. Must contain latitude, longitude, and habitat columns. |
| lat_col | no | "decimalLatitude" | Character. Latitude column name. Default "decimalLatitude". |
| lon_col | no | "decimalLongitude" | Character. Longitude column name. Default "decimalLongitude". |
| habitat_col | no | "main_habitat" | Character. Habitat assignment column name. Default "main_habitat". |
| coast_buffer_m | no | 1000 | Numeric. Buffer distance (metres) around coastlines for habitat classification. Points within this buffer are not flagged as marine/freshwater inconsistencies. The 1 km default accounts for GPS coordinate uncertainty, tidal zones, and coastal habitat gradients. Default 1000. |
| marine_questionable_km | no | 0 | Numeric. If greater than zero, marine species within this distance (km) of the coastline are flagged as "questionable" rather than "likely", on the grounds that very nearshore points may warrant visual verification. Default 0 (disabled) -- all marine species in ocean are "likely" regardless of distance to shore. Set e.g. 0.1 to flag points within 100 m of the shoreline. |
| depth_neritic_m | no | 200 | Numeric. Depth threshold (metres) defining the neritic (continental shelf) zone. Points shallower than this are classified as nearshore. The 200 m convention follows the standard oceanographic definition of the continental shelf edge. Default 200. |
| depth_oceanic_m | no | 4000 | Numeric. Depth threshold (metres) defining the boundary between bathyal and abyssal zones. Follows the standard oceanographic depth zonation. Default 4000. |
| resolution | no | 4L | Integer. Bathymetry resolution in arc-minutes for the NOAA GEBCO download. Used only for depth classification of confirmed marine points -- does not affect land/ocean classification. Default 4. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |
| habitat_scheme | no | NULL | Optional. A habitat_prompt object or habitat scheme dataframe used to resolve habitat names for depth/distance checks. If NULL, checks rely on the habitat_col values directly. |

**Value:** The input 'occurrence_data' dataframe with four additional columns: elevation_m Numeric. GEBCO value at the point: negative values are ocean depth in metres; positive values are approximate land elevation. Diagnostic only - land/ocean classification uses vector polygons, not this value. dist_to_coast_km Numeric. Distance in kilometres to the nearest coastline, rounded to 2 decimal places. spatial_

### flag_institution_candidates(occurrence_data, kingdom_col = "kingdom", suspicion_rules = NULL)

Tier Institution-Proximity Flags by Suspicion

Classification stage for the records 'TaxaFetch::filter_gbif_quality()' flags as near a biodiversity institution ('institution_flag = TRUE'). Proximity alone is a weak signal: a live fish record near a university's botanical garden pond and an herbarium sheet near the same garden mean very different things. This function narrows that down using the matched institution's own 'type' (from 'CoordinateCleaner::institutions') crossed against the record's 'kingdom' - a herbarium match for a plant is a real concern; a herbarium match for a fish essentially never is.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe, typically the output of TaxaFetch::filter_gbif_quality(). Must contain institution_flag and institution_type (both added by that function when flag_institution = TRUE, its default). |
| kingdom_col | no | "kingdom" | Character. Column holding each record's kingdom. Default "kingdom" (GBIF's standard column name). |
| suspicion_rules | no | NULL | A dataframe with columns institution_type, kingdom, suspicion ("high" or "low") used to classify flagged records. kingdom = NA in a rule means "any kingdom for this institution type." A flagged record whose (institution_type, kingdom) combination doesn't match any rule -- including every "Museum", "University", and "Research_centre" match by default, since none are listed below -- gets "ambiguous". Default rules (a first-pass heuristic, not a settled taxonomy -- override freely): institution_type kingdom suspicion Herbarium Plantae high Herbarium Fungi high Herbarium <NA> low Botanic_garden Plantae high Botanic_garden <NA> low Zoo Animalia high Zoo <NA> low "Museum"/"University"/"Research_centre" are deliberately absent from the default rules -- real institutions of these types range from pure specimen archives to active field stations sited at the exact habitat they study (e.g. a marine lab on its own shoreline), and institution_type alone cannot tell those apart. That's exactly the case review_institution_flags exists for. |

**Value:** 'occurrence_data' with one additional column, 'institution_suspicion': '"high"', '"low"', or '"ambiguous"' for a flagged record ('institution_flag = TRUE'); 'NA' for every other record (never checked - mirrors 'flag_habitat_inconsistencies''s convention of never conflating "not evaluated" with a real category).

### parse_hierarchical_habitat_response(raw_text, taxon_list, habitat_scheme = NULL, extra_covariates = NULL)

Parse a Weighted Habitat Response from an LLM

Parses the raw text returned by any LLM in response to a 'build_habitat_prompt' prompt into a species-by-habitat weight table. Provider-neutral: works with the multi-chunk dispatcher ('prompt_api' with any 'llm_fn'), any direct 'call_*_api()' function, user-written provider functions, and manually saved response files ('read_llm_response').

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character. Length-1 string containing the LLM response. Markdown code fences, leading/trailing preamble, and postamble text are handled automatically. |
| taxon_list | yes |  | Character vector. Species submitted in the prompt. Used to detect taxa missing from the response. |
| habitat_scheme | no | NULL | A habitat_prompt object from build_habitat_prompt. Always supply this -- its $habitat_cols element is used to identify and validate the weight columns, and its $scheme drives IUCN vs. custom mode. NULL triggers legacy IUCN mode (deprecated; IUCN output is also now wide-weighted). |
| extra_covariates | no | NULL | Character vector. Names of any additional binary covariate columns to retain from the parsed output. Default NULL (no extra columns retained). Ignored when no matching columns are found. |

**Value:** A data.frame with one row per species and the following columns: taxon_name Character. Species name as returned by the LLM. Numeric. One column per habitat in the scheme, named exactly as in 'prompt$habitat_cols'. Values are 0.0-1.0. Other_weight Numeric. Weight assigned to habitats outside the scheme. 0 for specialists that fit the scheme. habitat_best_guess Character. Free-text description of th

### parse_scheme_response(raw_text, scheme_prompt = NULL)

Parse a Habitat Scheme Response from an LLM

Parses the raw CSV text returned by an LLM in response to a 'build_scheme_prompt' prompt into a 'habitat_scheme' dataframe ready for 'build_habitat_prompt'.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character. Raw LLM response from prompt_api or read_llm_response. |
| scheme_prompt | no | NULL | A scheme_prompt object from build_scheme_prompt. Used to validate the response against the requested min/max habitat counts. If NULL, validation is skipped. |

**Value:** A 'habitat_scheme' data.frame with columns 'l1_name' and 'realm', suitable for passing directly to 'build_habitat_prompt' as 'habitat_scheme'. The 'l2_name' and 'l2_code' columns are set to 'NA' (single-level scheme). Print the result to inspect and verify the suggested categories before proceeding.

### report_habitat(habitat_data, taxon_col = "scientificName", verbose = FALSE)

Generate a Report Section for Habitat Assignment

Summarizes the habitat assignment produced by TaxaHabitat into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| habitat_data | yes |  | Data frame. Output of assign_habitat_biological or the raw habitat weights from parse_hierarchical_habitat_response. Must contain at least one numeric habitat weight column. |
| taxon_col | no | "scientificName" | Character. Column name containing taxon names. Default "scientificName". |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing habitat assignment approach. results Template text summarizing habitat assignments. params Named list of habitat parameters. statistics Named list of summary counts.

### resolve_habitat_by_geography(occurrence_data, habitat_col = "main_habitat", lat_col = "decimalLatitude", lon_col = "decimalLongitude", candidate_mass = 0.8, coast_buffer_m = 1000, verbose = TRUE)

Resolve Unassigned Habitats From Point Geography

Fills in 'main_habitat' for points the assemblage consensus could not resolve, by asking where the point actually is. A taxon whose weights span freshwater, estuarine and marine is not uncertain about its habitat - it uses all three - so over open ocean it is marine, and inland it is not. The consensus threshold cannot express that, because it never sees the location.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | Output of assign_habitat_biological(), carrying a "habitat_proportions" attribute. Without it nothing can be resolved and the input is returned unchanged with a message. |
| habitat_col | no | "main_habitat" | Column names. |
| lat_col | no | "decimalLatitude" | Column names. |
| lon_col | no | "decimalLongitude" | Column names. |
| candidate_mass | no | 0.8 | Passed to the candidate rule; see review_spatial_flags(). |
| coast_buffer_m | no | 1000 | Half-width of the coastal band, in metres. Points within it are treated as shoreline and left unresolved. Default 1000, matching flag_habitat_inconsistencies(). |
| verbose | no | TRUE | Logical. Report what was resolved. |

**Value:** 'occurrence_data' with 'main_habitat' filled in where geography was decisive, plus a 'habitat_source' column. The '"habitat_proportions"' attribute is preserved.

### review_institution_flags(occurrence_data, lat_col = "decimalLatitude", lon_col = "decimalLongitude", taxon_col = "species", tile = "Esri.OceanBasemap", point_radius = 7)

Review Institution-Proximity Flags Interactively

Opens a Shiny gadget for reviewing records 'TaxaFetch:: filter_gbif_quality()' flagged as near a biodiversity institution ('institution_flag = TRUE'), tiered by 'flag_institution_candidates'. Each flagged record is shown on a map alongside its own matched institution's location, so a reviewer can see directly whether they coincide (an archived-specimen coordinate) or are genuinely apart (a real field observation near, but not at, the institution - e.g. a shoreline sample near a marine lab's own pier, versus its inland administrative campus).

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe, typically the output of flag_institution_candidates. Must contain institution_flag, institution_suspicion, institution_name, institution_type, institution_dist_m, institution_lon, institution_lat, and coordinate columns. |
| lat_col | no | "decimalLatitude" | Character. The record's own coordinate columns (not the institution's). Default "decimalLatitude"/ "decimalLongitude" (GBIF standard names). |
| lon_col | no | "decimalLongitude" | Character. The record's own coordinate columns (not the institution's). Default "decimalLatitude"/ "decimalLongitude" (GBIF standard names). |
| taxon_col | no | "species" | Character or NULL. Column for the species label shown in tooltips. Default "species". |
| tile | no | "Esri.OceanBasemap" | Character. Leaflet tile provider. Default "Esri.OceanBasemap". |
| point_radius | no | 7 | Numeric. Base circle marker radius in pixels. Occurrence markers are drawn at point_radius * 0.75; institution reference markers at point_radius * 0.5 (smaller and a distinct blue, so they provide spatial context without obscuring nearby occurrence points). Default 7. |

**Value:** 'occurrence_data' with one additional column, 'institution_decision': '"keep"' or '"remove"' for every record that had 'institution_flag = TRUE'; 'NA' for every other record (never shown to the reviewer, never touched). Returns 'NULL' if the user clicks Cancel.

### review_spatial_flags(occurrence_data, habitat_col = "main_habitat", lat_col = "decimalLatitude", lon_col = "decimalLongitude", taxon_col = "taxon_name", colors = NULL, tile = "Esri.OceanBasemap", point_radius = 6, bulk_confirm_threshold = 10000L, bulk_max = 100000L, candidate_mass = 0.8, viewer = shiny::paneViewer(minHeight = 450))

Review and Correct Spatial Flags Interactively

Opens a Shiny gadget for reviewing the 'spatial_flag' column added by 'flag_habitat_inconsistencies'. Points are shown in three views - *Likely*, *Questionable*, and *Unlikely* - corresponding to the three 'spatial_flag' values. Clicking a point reassigns it according to simple rules designed for a top-to-bottom review workflow.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe output of flag_habitat_inconsistencies. Must contain spatial_flag, spatial_flag_reason, point_id, and coordinate columns. |
| habitat_col | no | "main_habitat" | Character. Habitat column for point colouring. Default "main_habitat". |
| lat_col | no | "decimalLatitude" | Character. Latitude column. Default "decimalLatitude". |
| lon_col | no | "decimalLongitude" | Character. Longitude column. Default "decimalLongitude". |
| taxon_col | no | "taxon_name" | Character or NULL. Taxon column for the Point Info species display. Default "taxon_name". |
| colors | no | NULL | Named character vector mapping habitat labels to colours. NULL uses the standard ecological palette. |
| tile | no | "Esri.OceanBasemap" | Character. Leaflet tile provider. Default "Esri.OceanBasemap". |
| point_radius | no | 6 | Numeric. Circle marker radius in pixels. Default 6. |
| bulk_confirm_threshold | no | 10000L | Integer. A rectangle/polygon selection larger than this asks for confirmation, reporting the exact point count, before the action is applied. Default 10000L. Set to Inf to never ask. |
| bulk_max | no | 100000L | Integer. Hard ceiling: a selection larger than this is refused outright rather than applied, and the reviewer is asked to split the shape. Default 100000L. |
| candidate_mass | no | 0.8 | Numeric in (0, 1]. When occurrence_data carries a "habitat_proportions" attribute (from assign_habitat_biological), the Reassign Habitat dropdown offers only the habitats that together account for this much of the selection's own consensus vector, highest first. Default 0.8. Set to 1 to offer every habitat with a non-zero proportion. |
| viewer | no | shiny::paneViewer(minHeight = 450) | Shiny viewer function passed through to runGadget. Default shiny::paneViewer(minHeight = 450) (RStudio's embedded Viewer pane). Some RStudio configurations have been observed to silently swallow leaflet-map click events inside the Viewer pane; pass shiny::browserViewer() to force the gadget into a real browser tab as a workaround/diagnostic if map clicks appear unresponsive. |

**Value:** The input 'occurrence_data' dataframe with 'spatial_flag', 'spatial_flag_reason', and 'main_habitat' updated where changed. Returns 'NULL' if the user clicks Cancel. Filter to keep confirmed records: reviewed <- review_spatial_flags(occurrences_flagged) occurrences_clean <- dplyr::filter(reviewed, spatial_flag == "likely")

### save_spatial_review_decisions(reviewed, path, before = NULL, point_id_col = "point_id", flag_col = "spatial_flag", habitat_col = "main_habitat")

Save a reviewer's spatial-flag decisions

Extracts one row per 'point_id' from 'review_spatial_flags()''s output - the reviewed 'spatial_flag' and 'main_habitat' - and merges it into the decisions file at 'path' (a newer decision for the same point replaces the older one).

| Param | Required | Default | Doc |
|---|---|---|---|
| reviewed | yes |  | Data frame returned by review_spatial_flags (must carry point_id, spatial_flag, main_habitat). |
| path | yes |  | Character. The .rds decisions file, one per site. |
| before | no | NULL | Optional data frame: the table the gadget was opened on (flag_habitat_inconsistencies()'s output). When supplied, a point's habitat is recorded as a reviewer REASSIGNMENT only where it differs from before; otherwise the habitat is treated as the automatic assignment of the day and is NOT frozen for later runs. Without before, this function cannot tell an automatic habitat from a reviewer reassignment at all: every non-NA main_habitat in reviewed is recorded as a reassignment (the conservative reading) and will be re-applied VERBATIM by apply_spatial_review_decisions on every later run -- freezing that point's habitat at whatever the automatic classifier happened to say the day it was reviewed, even if the classifier's own logic later changes for the better. Pass before whenever the pre-review table is available to avoid this. |
| point_id_col | no | "point_id" | Column names. Defaults match review_spatial_flags()'s output. |
| flag_col | no | "spatial_flag" | Column names. Defaults match review_spatial_flags()'s output. |
| habitat_col | no | "main_habitat" | Column names. Defaults match review_spatial_flags()'s output. |

**Value:** Invisibly, the merged decisions table ('point_id', 'spatial_flag', 'main_habitat', 'habitat_reassigned', 'decided_at').

### taxahabitat_clear_cache(cache_dir = tools::R_user_dir("TaxaHabitat", "cache"), older_than_days = NULL, dry_run = FALSE)

Report and clear TaxaHabitat's on-disk habitat-verdict cache

Lists, and optionally deletes, the per-taxon files written by 'build_habitat_lookup()' when it is given a 'cache_dir'. Entries have no built-in expiry - a verdict stays valid until the scheme, covariates, context, or 'cache_tag' change, which changes its key and makes it a miss anyway - so pruning is about disk usage and about deliberately forcing a fresh classification, not about correctness.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaHabitat", "cache") | Character. The directory passed to build_habitat_lookup()'s cache_dir. Defaults to tools::R_user_dir("TaxaHabitat", "cache"), matching the sibling packages; workflows that pass a project-local directory should pass the same one here. |
| older_than_days | no | NULL | Optional numeric. Delete only entries older than this many days. NULL (default) considers every entry. |
| dry_run | no | FALSE | Logical. TRUE reports what would be deleted without deleting it. |

**Value:** Invisibly, the inventory data frame ('TaxaTools::list_cache_files()' output) of the files considered.

## Quick Start

``` r
library(TaxaHabitat)

# 1. Build an LLM prompt for habitat classification
prompt <- build_habitat_prompt(
  c("Fundulus parvipinnis", "Cottus asper", "Anas platyrhynchos")
)

# 2. Submit to an LLM provider
raw_text <- TaxaTools::prompt_api(prompt)

# 3. Parse response into per-species habitat weights
habitat_weights <- parse_hierarchical_habitat_response(raw_text, prompt)
# taxon_name           Marine_weight  Freshwater_weight  Terrestrial_weight
# Fundulus parvipinnis  0.85           0.15               0.0
# Cottus asper          0.0            1.0                0.0
# Anas platyrhynchos    0.05           0.60               0.35

# Steps 1-3 in one call, with a per-taxon on-disk cache -- what every
# production workflow should use. A habitat verdict decides which occurrence
# records count toward a habitat-stratified site prior downstream, so an
# uncached verdict that differs between two runs moves priors by orders of
# magnitude and makes the published taxon list irreproducible. Only taxa not
# already classified under the same scheme are sent to the LLM.
habitat_weights <- build_habitat_lookup(
  c("Fundulus parvipinnis", "Cottus asper", "Anas platyrhynchos"),
  cache_dir = "my_project_habitat_cache"
)
attr(habitat_weights, "cache_summary")   # n_from_cache / n_called

# 4. Assign habitat to sampling sites based on species composition
occurrences_with_habitat <- assign_habitat_biological(
  occurrences, habitat_weights
)

# 5. Flag spatial outliers (marine species at inland sites, etc.)
flagged <- flag_habitat_inconsistencies(occurrences_with_habitat)
```

