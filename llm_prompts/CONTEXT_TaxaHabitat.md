# CONTEXT: TaxaHabitat

**Habitat Assignment and Spatial Quality Control for Taxonomic Occurrences**

Assigns habitat classifications to taxonomic occurrence records using LLM prompts and performs spatial quality control. Receives occurrence data from TaxaFetch and produces habitat-annotated, spatially screened records for input to TaxaExpect. Part of the TaxaID ecosystem.

Version 1.0.0. 14 exported function(s).

## Functions

### apply_spatial_review_decisions(occurrence_data, path, point_id_col = "point_id", flag_col = "spatial_flag", reason_col = "spatial_flag_reason", habitat_col = "main_habitat", taxon_col = "taxon_name")

Apply saved spatial-flag decisions before (or instead of) the gadget

Overwrites 'spatial_flag' on every row whose '(point_id, taxon_name)' has a saved decision (and 'main_habitat' where the decision was a reviewer reassignment), marks the reason, and reports how many flagged points still need a reviewer. Call it on 'flag_habitat_inconsistencies''s output; open 'review_spatial_flags' only when 'attr(result, "n_pending_review") > 0' (or when you deliberately want to re-review). A missing decisions file is not an error: nothing is applied and every flagged point is pending.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | Data frame from flag_habitat_inconsistencies (carries point_id, spatial_flag, spatial_flag_reason, main_habitat, and ideally taxon_col -- see Details). |
| path | yes |  | Character. The decisions file written by save_spatial_review_decisions. |
| point_id_col | no | "point_id" | Column names. |
| flag_col | no | "spatial_flag" | Column names. |
| reason_col | no | "spatial_flag_reason" | Column names. |
| habitat_col | no | "main_habitat" | Column names. |
| taxon_col | no | "taxon_name" | Character. Name of the taxon column in occurrence_data. Default "taxon_name". Used to match a decision's saved taxon_name against the correct rows, and to detect an ambiguous point for an old-format decision (see Details). |

**Value:** 'occurrence_data' with decisions applied and attributes 'n_applied' (rows changed), 'n_pending_review' (distinct points with at least one row whose flag is not '"likely"' and that was not resolved by a decision this call - including a point left ambiguous, see Details) and 'pending_point_ids'.

#### Details

A saved spatial_flag and a saved reassigned main_habitat are both re-applied AS-IS -- neither is re-validated against the current run's own automatic classification. If the automatic classifier's logic changes between the run that produced a decision and a later run, the saved decision still overwrites whatever the newer automatic classification would have said, silently.

#### Old-format decisions files (no taxon_name)

A decisions file saved before save_spatial_review_decisions started recording taxon_name has no way to say which taxon a decision was for. Applying it verbatim by point_id alone would risk handing one taxon's reviewer fix to a different taxon sharing the same coordinates -- so instead, a decision with no recorded taxon is applied only where point_id_col identifies exactly one distinct taxon_col value in occurrence_data. Where the current data has more than one taxon at that point_id, nothing is applied: the point is left pending (it will reappear in pending_point_ids and in review_spatial_flags), a single warning() reports how many such points there are (first 20 ids), and a message() explains that re-reviewing and re-saving those points writes the newer (point_id, taxon_name) key, after which this function applies them normally. The same rule applies to any individual decision row saved without taxon information, even inside an otherwise new-format file.

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

**Value:** The input 'occurrence_data' with four additional columns: main_habitat Character. The winning habitat label at each point, or '"Uncertain"' if no habitat reached 'threshold'. *Not 'NA'*: 'NA' in a 'main_habitat' column already means _habitat-agnostic, matches any habitat_ on the prior side, where 'TaxaExpect::generate_domestic_food_priors()' sets it deliberately and 'TaxaAssign::join_priors()' reads it to build the wildcard tier for domestic and food taxa. An unplaceable occurrence would otherwise be indistinguishable from a chicken and inherit those semantics by accident, rather than being routed to the evidence branch and still counted as regionally present. '"Other"' appears here when the 'Other_weight' column wins, signalling that the community at this point does not fit the scheme. habitat_best_guess Character. Non-empty only when 'main_habitat = "Other"' (or when the leading habitat is listed but Other_weight is substantial). Concatenates the unique 'habitat_best_guess' values from all species at the point that contributed weight to 'Other_weight', separated by '"; "'. Use this to decide whether the habitat scheme needs extending. main_habitat_prop Numeric, 0 to 1. The proportion attained by the leading habitat at that point. Populated *regardless of* 'threshold', so it is defined for points where 'main_habitat' is 'NA' - which is what makes it useful. main_habitat_breadth Numeric. Levins' niche breadth of the point's consensus vector, in effective number of habitats: '1' is an unambiguous point, higher means a genuinely mixed assemblage. '"Other"' is excluded from the calculation. See Details. The full per-point consensus vector is attached as 'attr(result, "habitat_proportions")': one row per point, one column per habitat (including 'Other').

#### Details

This is a fallback method for when spatial polygon layers are unavailable.

Reading an NA habitat: two very different points can both come back as main_habitat = NA -- one clearly Marine at 0.28, just under a 0.3 threshold, and one genuinely mixed at 0.35 / 0.33 / 0.32. The first has an unambiguous signal the threshold rejected; the second has no signal to have. main_habitat_prop separates them and main_habitat_breadth quantifies the spread, both defined for points the threshold rejected. A point with a high main_habitat_prop and a breadth near 1 is a candidate for a lower threshold; a point with breadth near the number of habitats is genuinely ambiguous and wants a reviewer, not a different cutoff.

How weighted consensus works: For each point, the function joins occurrence records to the habitat weight table. Each matched species contributes its full weight vector (one value per habitat column). If weight_by_abundance = FALSE, each species counts once; if TRUE, its weights are multiplied by its record count at the point. Column sums are normalised to proportions. The habitat with the largest proportion is assigned if it meets threshold.

Other_weight: Treated as a regular habitat column named "Other" throughout the computation. When it wins, main_habitat is set to "Other" and habitat_best_guess is populated from the habitat_best_guess column in habitats_df.

Species not in lookup table: Silently ignored -- they reduce the effective species count, making consensus harder to reach. Check coverage before running:


```

mean(unique(occurrence_data$taxon_name) %in% habitats_df$taxon_name) ```

### build_habitat_lookup(taxon_list, habitat_scheme = NULL, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), cache_dir = NULL, extra_covariates = character(0), chunk_size = 60L, geographic_context = NULL, cache_tag = "", pause_seconds = 1, verbose = TRUE, compound_rule = c("sum", "max"))

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
| compound_rule | no | c("sum", "max") | Passed to build_habitat_prompt(): "sum" (default) or "max". NOT part of the cache key: the cache holds the parts the model returned and the compound is re-derived from them on every call, so the rule can be changed without a single new model call. |

**Value:** A data frame with one row per unique taxon in 'taxon_list' (the same shape 'parse_hierarchical_habitat_response()' returns), in 'taxon_list' order, with a 'cache_summary' attribute: 'n_total', 'n_from_cache', 'n_called', 'n_cached_new'.

#### Why cache this at all

A habitat verdict decides which occurrence records count toward a habitat-stratified site prior in TaxaExpect. If the LLM answers differently on two runs, a species can move from "locally observed" to "locally undetected" (or back) with no change in the data, and every downstream call that species competes in moves with it. Caching makes an identical re-run reproduce the same priors, and makes the habitat step free after the first run. Nothing here changes what the LLM is asked or how its answer is parsed.

#### What the cache key covers

The taxon name, the habitat columns the scheme asks for (derived exactly as build_habitat_prompt() derives them, so a changed scheme is a miss), extra_covariates, geographic_context, and cache_tag. The LLM function itself cannot be hashed -- if you change providers or models and want fresh verdicts, pass a new cache_tag (e.g. the model name) or clear the directory with taxahabitat_clear_cache().

#### What is and is not cached

Only a taxon whose parsed row carries a resolved Habitat (at least one non-zero weight) is written. A taxon the LLM skipped, or that sat in a failed chunk, comes back with Habitat = NA and is NOT cached, so it is re-asked on the next run instead of being frozen as unknown.

### build_habitat_prompt(taxon_list, extra_covariates = character(0), chunk_size = 60L, habitat_scheme = NULL, geographic_context = NULL, compound_rule = c("sum", "max"))

Build a Habitat Assignment Prompt

Creates a 'habitat_prompt' object containing one or more LLM prompt strings for habitat assignment. This is always Step 1 of the habitat assignment pipeline, regardless of which submission path is used in Step 2.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_list | yes |  | Character vector of scientific names. |
| extra_covariates | no | character(0) | Character vector of additional binary (0/1) covariate names to request from the LLM alongside habitat weights. Default character(0) (no extra covariates). Provide a character vector (e.g. c("Invasive", "Migratory")) only when you intend to use the trait information downstream; extra covariates add tokens and output columns that are ignored by the rest of the habitat pipeline. |
| chunk_size | no | 60L | Integer. Maximum taxa per prompt chunk. Default 60. Larger lists are split into multiple chunks automatically. Reduce if your LLM has a small context window; increase cautiously for APIs with large windows. |
| habitat_scheme | no | NULL | A dataframe defining the habitat classification to use. An optional parts column declares a COMPOUND label's real parts (pipe-delimited habitat names; see the section Compound labels), the string "IUCN_L1", or NULL. NULL (default) uses a simple three-category scheme: Marine, Freshwater, Terrestrial. This is always a valid starting point and is always interpretable in a model. "IUCN_L1" uses the 18 IUCN Level 1 group names as a single-level scheme. Pass a dataframe for a custom scheme (must contain l1_name; optional: l2_name, l2_code, realm). See example_habitat_scheme for a dataframe template. |
| geographic_context | no | NULL | Optional character string describing the geographic region where these species were observed (e.g. "Southern California", "Chesapeake Bay watershed"). When non-NULL, the prompt includes a geographic context block and requests an additional ecoregion_best_guess column from the LLM. Default NULL (no geographic context). |
| compound_rule | no | c("sum", "max") | "sum" (default) or "max": how a compound label's weight is derived from its parts. The parts are disjoint shares of the species' habitat use that sum to 1 with the plain labels, so the union's share is their SUM (capped at 1); "max" takes the largest part instead, which never falls below a component either but discards the other parts' shares. Ignored when no scheme row declares parts. |

**Value:** An object of class 'c("habitat_prompt", "llm_prompt")', which is a named list: prompts List of character strings, one per chunk. taxa Character vector of deduplicated, trimmed taxon names. chunks List of character vectors, taxa per chunk. scheme The validated habitat scheme dataframe. habitat_cols Character vector of habitat column names the LLM will produce (the scheme's working habitat names, in order). Used by 'parse_hierarchical_habitat_response' to identify weight columns. extra_covariates The covariate names used. geographic_context The geographic context string, or 'NULL'. chunk_size The chunk size used. n_chunks Integer. Number of chunks. Print the object for a summary. Pass to 'prompt_api' (Path 1/2) or 'prompt_manual' (Path 3).

#### Details

The LLM is asked to distribute habitat affinity as weights across all habitats in the scheme (summing to 1.0 per species), rather than picking a single habitat. This allows habitat generalists to contribute partial signal to multiple habitats at a sampling point. A special Other_weight column captures species whose ecology does not fit any listed habitat; these are flagged by habitat_best_guess for scheme review.

Output shape from the LLM: The LLM returns a CSV with one row per species. Each listed habitat is a column containing a numeric weight (0.0-1.0). All habitat weights plus Other_weight sum to 1.0.

#### Compound labels

A scheme label that names several habitats at once ("Coastal-Marine- Estuary-Stream" for a stream-fed lagoon) is one column to the model, and a model scores one column as one habitat: in practice it reads the marine words and ignores the rest, so a stream fish can score lower on the compound than on "Coastal-Stream", a label the compound contains. A scheme row may therefore DECLARE the label's real parts in a parts column, a pipe-delimited list of habitat names ("Marine|Estuary|Stream" for the lagoon; "Stream" for "Coastal-Stream", because "Coastal" is a modifier, not a habitat). The model then never sees the compound as a scorable column: it weights the parts (a part that is itself a plain label is asked once and serves both), and a species that uses ANY part of a site uses the site, so the compound's weight is the SUM of its parts' shares, capped at 1 (compound_rule = "sum"): it is never below any part, by construction. The alternative "max" keeps only the largest part; because the model's sum-to-1 budget is spread over more columns once a compound is split, "max" systematically LOWERS the compound for the species that use several of its parts (an estuarine resident scored 0.5 Estuary + 0.3 Marine + 0.1 Stream reads 0.5 under max, 0.9 under sum). The derived column is NOT part of the sum-to-1 constraint (the parts are), so a lookup built this way has scheme columns that can sum above 1; every consumer in this ecosystem reads a weight as a per-habitat affinity, not as a share, so that is harmless, and the breadth statistic renormalises. Parts are declared, never derived from a label's spelling: splitting "Coastal-Stream" on its hyphen would score "Coastal" as a habitat and hand every marine species a coastal share. The returned object records the mapping in $compounds and the scheme's own labels in $scheme_cols; $habitat_cols is what the model is asked to output. Only a single-level scheme may declare parts. habitat_best_guess is a free-text column populated only when Other_weight > 0; it records the LLM's best description of the species' actual habitat for scheme review.

Pipeline:


```

prompt <- build_habitat_prompt(taxa_in_data) raw_text <- TaxaTools::prompt_api(prompt) # Path 1 # OR TaxaTools::prompt_manual(prompt) # Path 3 raw_text <- TaxaTools::read_llm_response("habitat_response_1.txt")

hab_tbl <- parse_hierarchical_habitat_response(raw_text, taxa_in_data, habitat_scheme = prompt) ```

Chunking: For lists longer than chunk_size, the taxon list is split into chunks and one prompt string is built per chunk. Each chunk is self-contained. Chunks must be submitted and parsed independently; do not concatenate prompts before submitting.

### consensus_habitat(habitats_df, habitat_cols = NULL, taxon_col = "taxon_name", threshold = 0.3)

Compute Assemblage-Level Consensus Habitat

Summarises per-species habitat weights into a single consensus habitat (and optionally ecoregion) for the entire assemblage. Each species contributes equally. Useful for inferring site-level habitat context from a list of candidate taxon names when occurrence records or spatial data are unavailable.

| Param | Required | Default | Doc |
|---|---|---|---|
| habitats_df | yes |  | A dataframe of per-species habitat weights, as produced by parse_hierarchical_habitat_response. Must contain a column named by taxon_col and one or more numeric habitat weight columns. |
| habitat_cols | no | NULL | Character vector naming the habitat weight columns. If NULL (default), auto-detected (all numeric columns except taxon_col and text columns). |
| taxon_col | no | "taxon_name" | Character. Name of the taxon name column. Default "taxon_name". |
| threshold | no | 0.3 | Numeric in (0, 1]. Minimum habitat weight fraction for a habitat to be classified as biologically relevant. At 0.3, a habitat must receive at least 30% of the species-weighted votes to be assigned. Lower values include more marginal habitats; higher values restrict assignment to clearly dominant habitats. For transitional areas (e.g., estuaries), a lower threshold (0.2) may better capture mixed habitats. Default 0.3. |

**Value:** A one-row data frame with columns: main_habitat Character. The consensus habitat, or 'NA' if none reached 'threshold'. *Deliberately 'NA', and deliberately unlike 'assign_habitat_biological'*, which returns the sentinel '"Uncertain"' for the same condition. See Details. ecoregion Character. The modal 'ecoregion_best_guess' value across species, or 'NA' if the column is absent. habitat_best_guess Character. Concatenated free-text guesses when '"Other"' wins, otherwise 'NA'. The full habitat proportion vector is attached as 'attr(result, "habitat_proportions")'.

#### Details

Why this returns NA when assign_habitat_biological returns "Uncertain". The two functions compute the same quantity at different scales, and only one of them feeds the occurrence table. assign_habitat_biological() labels occurrence points, where NA was already taken: on the prior side NA in a main_habitat column means habitat-agnostic, matches any habitat (the domestic/food wildcard tier built by TaxaExpect::generate_domestic_food_priors() and read by TaxaAssign::join_priors()). A point whose habitat could not be determined is not habitat-agnostic, so it needed its own sentinel.

consensus_habitat() returns a site-level scalar consumed by TaxaAssign::build_context(), which never reaches the prior join and so never had the collision. Changing it would not fix a bug; it would introduce one. build_context() tests its LLM synthesis result with a bare is.na() and falls back to this function's value when synthesis fails, then writes the result into ctx$main_habitat, which is rendered into a prompt and used to resolve a site. Were this function to return "Uncertain", that fallback would hand the literal string to all of it, and a site would be resolved against an "Uncertain" stratum.

So the divergence is load-bearing, not an oversight. Anyone changing it must change TaxaAssign::build_context()'s fallback in the same commit.

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

**Value:** The input 'occurrence_data' dataframe with four additional columns: elevation_m Numeric. GEBCO value at the point: negative values are ocean depth in metres; positive values are approximate land elevation. Diagnostic only - land/ocean classification uses vector polygons, not this value. dist_to_coast_km Numeric. Distance in kilometres to the nearest coastline, rounded to 2 decimal places. spatial_flag Character. One of '"likely"', '"questionable"', or '"unlikely"'. spatial_flag_reason Character. Plain-English explanation including numeric context (e.g. distance inland, depth).

#### Details

In this project's real usage so far, the most common error this function catches is a marine species assigned a marine habitat but located far inland -- a GBIF georeferencing error. This reflects the datasets this package has been used with to date, not a universal claim about GBIF data quality generally. Terrestrial species appearing in the ocean are also flagged.

The function adds four columns to the input dataframe, repeated for every row sharing the same location, so the dataframe structure and row count are unchanged. The augmented object can be passed directly to review_spatial_flags for interactive visual review, and filtered numerically using dist_to_coast_km and elevation_m for a non-interactive workflow.

#### Physical zone classification

Land/ocean classification uses Natural Earth country polygons (vector), which correctly handles enclosed water bodies like bays, estuaries, and inland seas that raster-based approaches misclassify at low resolution. Coastal zone is a buffer around the Natural Earth coastline. Ocean depth for confirmed marine points comes from NOAA GEBCO bathymetry.

- inland: Inside land polygon and distance to coast > coast_buffer_m.

- coastal: Within coast_buffer_m of the coastline, on either side. Captures intertidal and supralittoral zones.

- marine_shallow: Outside land polygon, outside coastal buffer, ocean depth 0 to depth_neritic_m metres.

- marine_deep: Ocean depth depth_neritic_m to depth_oceanic_m metres.

- marine_abyssal: Ocean depth > depth_oceanic_m metres.

#### Freshwater habitats

Habitats classified as the "freshwater" realm (via the scheme's own realm column when present, or by name pattern -- matching "freshwater", "wetland", "aquatic", "lake", "river", "stream", "pond", "marsh", "bog", "fen", or "riparian") are silently assigned spatial_flag = "likely" with reason "freshwater habitat not spatially verified". This avoids false positives for a common and genuinely hard-to-check class.

### flag_institution_candidates(occurrence_data, kingdom_col = "kingdom", suspicion_rules = NULL)

Tier Institution-Proximity Flags by Suspicion

Classification stage for the records 'TaxaFetch::filter_gbif_quality()' flags as near a biodiversity institution ('institution_flag = TRUE'). Proximity alone is a weak signal: a live fish record near a university's botanical garden pond and an herbarium sheet near the same garden mean very different things. This function narrows that down using the matched institution's own 'type' (from 'CoordinateCleaner::institutions') crossed against the record's 'kingdom' - a herbarium match for a plant is a real concern; a herbarium match for a fish essentially never is.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | A dataframe, typically the output of TaxaFetch::filter_gbif_quality(). Must contain institution_flag and institution_type (both added by that function when flag_institution = TRUE, its default). |
| kingdom_col | no | "kingdom" | Character. Column holding each record's kingdom. Default "kingdom" (GBIF's standard column name). |
| suspicion_rules | no | NULL | A dataframe with columns institution_type, kingdom, suspicion ("high" or "low") used to classify flagged records. kingdom = NA in a rule means "any kingdom for this institution type." A flagged record whose (institution_type, kingdom) combination doesn't match any rule -- including every "Museum", "University", and "Research_centre" match by default, since none are listed below -- gets "ambiguous". Default rules (a first-pass heuristic, not a settled taxonomy -- override freely): institution_type kingdom suspicion Herbarium Plantae high Herbarium Fungi high Herbarium <NA> low Botanic_garden Plantae high Botanic_garden <NA> low Zoo Animalia high Zoo <NA> low "Museum"/"University"/"Research_centre" are deliberately absent from the default rules -- real institutions of these types range from pure specimen archives to active field stations sited at the exact habitat they study (e.g. a marine lab on its own shoreline), and institution_type alone cannot tell those apart. That's exactly the case review_institution_flags exists for. |

**Value:** 'occurrence_data' with one additional column, 'institution_suspicion': '"high"', '"low"', or '"ambiguous"' for a flagged record ('institution_flag = TRUE'); 'NA' for every other record (never checked - mirrors 'flag_habitat_inconsistencies''s convention of never conflating "not evaluated" with a real category).

#### Details

This is a pure classification step -- no interaction, no rows removed or reordered, mirroring flag_habitat_inconsistencies's role ahead of an interactive review gadget. It adds one column (institution_suspicion) and makes no other change to occurrence_data.

### parse_hierarchical_habitat_response(raw_text, taxon_list, habitat_scheme = NULL, extra_covariates = NULL)

Parse a Weighted Habitat Response from an LLM

Parses the raw text returned by any LLM in response to a 'build_habitat_prompt' prompt into a species-by-habitat weight table. Provider-neutral: works with the multi-chunk dispatcher ('prompt_api' with any 'llm_fn'), any direct 'call_*_api()' function, user-written provider functions, and manually saved response files ('read_llm_response').

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_text | yes |  | Character. Length-1 string containing the LLM response. Markdown code fences, leading/trailing preamble, and postamble text are handled automatically. |
| taxon_list | yes |  | Character vector. Species submitted in the prompt. Used to detect taxa missing from the response. |
| habitat_scheme | no | NULL | A habitat_prompt object from build_habitat_prompt. Always supply this -- its $habitat_cols element is used to identify and validate the weight columns, and its $scheme drives IUCN vs. custom mode. NULL triggers a reduced IUCN-only mode; passing a habitat_prompt object uses the full wide-weighted format instead. |
| extra_covariates | no | NULL | Character vector. Names of any additional binary covariate columns to retain from the parsed output. Default NULL (no extra columns retained). Ignored when no matching columns are found. |

**Value:** A data.frame with one row per species and the following columns: taxon_name Character. Species name as returned by the LLM. Numeric. One column per habitat in the scheme, named exactly as in 'prompt$habitat_cols'. Values are 0.0-1.0. Other_weight Numeric. Weight assigned to habitats outside the scheme. 0 for specialists that fit the scheme. habitat_best_guess Character. Free-text description of the actual habitat for species with non-zero 'Other_weight'. Empty string otherwise. Habitat Character. Convenience column: name of the habitat column with the highest weight (argmax), ties broken by column order. '"Other"' when 'Other_weight' is the largest, 'NA' when all weights are zero. *Diagnostic only* - see Details; nothing in the pipeline consumes it as a habitat assignment. habitat_breadth Numeric. Levins' niche breadth, 'B = 1 / sum(p^2)', over the scheme's habitat columns with the weights renormalised to sum to 1, in units of *effective number of habitats*: '1' is a pure specialist and the maximum is the number of habitat columns. 'NA' when all scheme weights are zero. See Details for why it exists and how to read it with 'Other_weight'.

#### Details

Multi-chunk responses: If raw_text contains multiple CSV blocks (one per chunk from prompt_api), duplicate header rows are stripped automatically before combining.

The Habitat column is diagnostic only. assign_habitat_biological sums each species' full WEIGHT VECTOR per point and never reads it. Audited across all nine TaxaID packages, its only functional consumer is build_habitat_lookup, which uses !is.na(Habitat) to decide whether a verdict is resolved enough to cache. Do not build on it as a habitat assignment: for a per-taxon habitat use the weight columns, for a per-location one use main_habitat, and to judge how meaningful the label is for a given taxon read habitat_breadth beside it.

Habitat breadth: Habitat is an argmax, so it renders a near-uniform weight vector and a decisive one as the same confident-looking string. On the real PtConception 12S lookup, Larus delawarensis and Chroicocephalus philadelphia carry identical weights (Marine 0.30, Estuarine 0.20, Freshwater 0.30, Terrestrial 0.20) and both read "Marine", while Gelochelidon nilotica (0.20/0.20/0.30/0.30) reads "Freshwater" -- the label is decided by column order. habitat_breadth recovers what the argmax discards. Standardise it to 0-1 with (B - 1) / (n - 1) if needed.

Other_weight is deliberately excluded from the breadth calculation: it measures the model failing to place a taxon in the scheme at all, which is a different quantity from a taxon that genuinely spans habitats. Read the two together -- high breadth with low Other_weight is a real generalist, whereas high Other_weight means the verdict itself is weak.

Declared weight columns: the returned data frame carries an "habitat_cols" attribute naming the weight columns, and assign_habitat_biological prefers it over scanning for numeric columns. Do not add a numeric column to this table without checking that attribute is set: the type scan is the fallback, and it would absorb the new column as an extra habitat weight.

Compound labels: when habitat_scheme is a prompt object whose scheme declares parts, the model returns the compounds' PARTS as columns and this function derives each compound label's weight from its parts (the sum of their shares, capped at 1, or the max; see build_habitat_prompt's compound_rule), so the compound is never below any part. The output then carries the scheme's own labels (the compounds and the plain labels) as its habitat columns, declared in the "habitat_cols" attribute, with the part columns kept after them for inspection. The sum-to-1 check runs over the columns the model returned, not over the derived ones.

Weight normalisation: Weights are NOT renormalised. A warning is emitted for any row where weights deviate more than 0.05 from 1.0.

Unrecognised columns: If the LLM returns habitat column names not in prompt$habitat_cols, those columns are folded into Other_weight with a warning.

Missing species: Taxa in taxon_list absent from the parsed output trigger a warning listing the first five missing names.

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

#### Details

Only points with exactly one admissible candidate are resolved. A point at the shoreline, where the map cannot separate marine from estuarine from terrestrial, is left unassigned deliberately: that is a real ambiguity and belongs in review_spatial_flags(), not in an automatic rule.

#### What resolves, and what does not

- ocean: Only a marine, non-estuarine candidate.

- inland: Any non-marine candidate. Resolves only when one such candidate exists -- a Freshwater | Terrestrial point inland stays ambiguous, because without a lake or river layer the map cannot tell a pond from a hillside.

- coastal: Nothing. Every habitat is admissible within coast_buffer_m of the shore, so geography discriminates nothing.

Measured on the full production PtConception 12S pool (220,311 points, 31,383 unassigned): 6,222 points resolved, 20% -- 2,940 ocean, 3,282 inland -- leaving 25,161 where geography discriminates nothing. 5.9 seconds.

A 6,523-point coastal extract of the same site gives 34% (221 of 646), but it is not representative: the extract is coastal-heavy, and its unassigned points are Cottidae, whereas production's are 97%-by-record birds (Laridae, Anatidae, Gaviidae). Quote the production number. The general lesson is that a fixture chosen for convenience validated the mechanism without exercising the case that matters.

What it resolves in production is itself worth knowing: 27,400 records, of which 97% are birds -- Laridae 17,737, Anatidae 3,095, Gaviidae 2,399, Phalacrocoracidae 2,004. Those records are currently excluded from the resident prior only because their habitat is unassigned, which is an accident rather than a scope decision. If birds are out of scope for the marker, filter families before the fetch; do not rely on this function declining to resolve them. Note also that the remaining 467,614 unassigned records stay unassigned -- most bird records sit at coastal points, where nothing resolves -- so the volume entering the prior is far smaller than the unassigned pool's size suggests.

#### Provenance

A resolved point gets habitat_source = "geography"; a point the consensus had already settled keeps "consensus". A geography-resolved habitat is a weaker claim than an assemblage consensus and it feeds habitat-stratified priors, so the distinction is recorded in the data rather than left to be inferred. The point's habitat_proportions vector is not rewritten -- the taxon really does use those habitats; only main_habitat is decided.

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

#### Details

Deliberately scoped down from review_spatial_flags: no rectangle bulk-select, no habitat reassignment, single-level undo. The institution-flagged subset of a real dataset is typically small (tens of records, not thousands), so a simple one-point-at-a-time review is enough; rebuild with bulk tools later if that stops being true.

#### Review workflow

- Every flagged record starts as Keep -- nothing is ever discarded just by opening this gadget or clicking Done without reviewing every point.

- Click a record's marker to toggle it to Remove (institution error, discard) or back to Keep (genuine observation, retain).

- Institution markers (blue squares) are shown for context -- clicking them does nothing.

- Click Done. Filter to keep confirmed-good records: dplyr::filter(result, institution_decision != "remove") (non-flagged rows keep institution_decision = NA and are always retained by that filter).

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

#### Review workflow

- Start in Likely view. Click any point that looks suspicious -- it moves to Questionable.

- Switch to Unlikely view. Click any point that actually looks fine -- it moves to Questionable.

- Switch to Questionable view. Click any point you are now satisfied with -- it moves to Likely.

- Click Done. The returned dataframe retains only the updated spatial_flag values.

- Filter to keep only confirmed good points: dplyr::filter(result, spatial_flag == "likely")

#### Click behaviour

The Action radio switches between two modes:

- Flag (default): Clicks reassign spatial_flag: Likely/Unlikely \rightarrow Questionable; Questionable \rightarrow Likely.

- Reassign Habitat: Click selects a point and shows a dropdown of all habitats present in the dataset (plus Other for a value not yet seen this session). Confirming updates main_habitat for all rows at that point_id. If the point's flag was Questionable at the moment of reassignment, this counts as a spatially-informed resolution and the flag becomes Likely (the point leaves the Questionable view). Reassigning from Likely/Unlikely keeps the point's existing flag -- the reassignment itself is treated as a spatially-informed decision, so it does not force a second round-trip through the Questionable view.

Every change appends a timestamped note to spatial_flag_reason. A habitat value typed via Other that doesn't already appear in the dataset is added to the palette and the Habitats sidebar filter immediately, without disturbing any existing habitat's colour.

#### What the reviewer is deciding

Two decisions drive this gadget, and neither is visible from the map, so an Instructions dialog states both on open (re-openable from the sidebar).

- Which points are trusted. likely points are kept for analysis; questionable and unlikely are excluded as probable errors. Anything left in the Questionable view is therefore dropped, which is why that view is worth inspecting.

- Which points get modelled. A point with no single main_habitat still counts as regionally present but is not modelled as resident: TaxaExpect::estimate_kernel_priors() requires a non-NA habitat, so those taxa fall through to the weaker regional-proximity evidence instead. Resolving a point's habitat promotes it.

#### Composite categories for unassigned points

A point whose consensus reached no verdict (main_habitat NA) is not left as a single undifferentiated Unknown -- which would make every ambiguous point look like the same problem, resolvable only one click at a time.

When occurrence_data carries a "habitat_proportions" attribute, such a point is labelled with the habitats actually in contention -- "Estuarine | Freshwater | Marine" -- and that label is a real category: its own colour, its own entry in the Habitats sidebar filter, and therefore selectable as a group. Filter to one signature, draw a polygon over a region, and reassign the lot to whichever habitat the location implies. Location disambiguates what the assemblage cannot.

Members are sorted alphabetically, not by proportion, so the same candidate set always lands in the same group; ordering by proportion would split one category across several permutations. Per-point proportions still appear in the Reassign dropdown.

The label is a display category only. main_habitat stays NA in the returned data until the point is actually reassigned -- the Done handler writes back only habitats that differ from what the gadget started with, so an untouched composite point keeps its NA rather than acquiring a signature string as its habitat.

#### Habitat candidates for reassignment

When occurrence_data carries a "habitat_proportions" attribute -- which assign_habitat_biological attaches and flag_habitat_inconsistencies preserves -- the Reassign Habitat dropdown offers what the point's own assemblage hypothesises, ordered by proportion and labelled with it, rather than the whole scheme. A point reading Freshwater 0.35 / Marine 0.30 / Estuarine 0.25 / Terrestrial 0.10 offers the first three at candidate_mass = 0.8.

The rule is cumulative mass rather than a fixed proportion cutoff, which barely reduces the list because the LLM emits round numbers.

The point's current habitat is always offered, even when it falls outside the mass, so a reassignment can be undone by hand. Other (free text) is always offered. A Show all habitats checkbox restores the full scheme and names how many were hidden -- use it when the consensus itself is what you are disputing. With no attribute present the dropdown offers everything.

#### Bulk selection (rectangle or polygon)

The map's draw toolbar offers a rectangle and a polygon. Both select every visible point of the current view that falls inside the drawn shape (the polygon suits non-rectangular boundaries such as a coastline or lake shore). In Flag mode the shape applies immediately; in Reassign Habitat mode it selects, and Confirm applies.

Selection size is gated, never truncated, because a partially applied selection would be invisible to the reviewer and indistinguishable in the output. At or below bulk_confirm_threshold the action applies straight away; above it a dialog reports the exact count and requires an explicit Apply; above bulk_max the action is refused with a message.

Each bulk action is recorded as ONE entry, so Undo Last reverses an entire selection in a single click.

The polygon test uses an even-odd ray cast in Web Mercator (matching the straight-line edges leaflet actually draws) and does not support a shape crossing the antimeridian.

#### Habitat filter

The sidebar Habitats panel lists every habitat present in the dataset (plus any added mid-session via a habitat reassignment) as a colour-coded checkbox. Unchecking a habitat hides those points from the map and excludes them from shape selection and click actions. Each entry carries the number of points it currently holds in the view on screen, so a category's size is visible before it is ticked and an emptied one is obvious; a category reduced to zero by reassignment is greyed and struck through rather than removed. Use All / None to select or clear all at once.

#### Point Info panel

Hovering over any map point updates the Point Info sidebar section with the point ID, its current habitat (reflecting any in-session reassignments), and taxon information. By default only the first species alphabetically and the total count are shown. Checking Show full species list expands the panel to display every taxon recorded at the hovered point as a scrollable inline list. The toggle does not affect hover or click behaviour.

### save_spatial_review_decisions(reviewed, path, before = NULL, point_id_col = "point_id", flag_col = "spatial_flag", habitat_col = "main_habitat", taxon_col = "taxon_name")

Save a reviewer's spatial-flag decisions

Extracts one row per '(point_id, taxon_name)' from 'review_spatial_flags()''s output - the reviewed 'spatial_flag' and 'main_habitat' - and merges it into the decisions file at 'path' (a newer decision for the same point/taxon replaces the older one).

| Param | Required | Default | Doc |
|---|---|---|---|
| reviewed | yes |  | Data frame returned by review_spatial_flags (must carry point_id, spatial_flag, main_habitat; taxon_name is used when present, see Details). |
| path | yes |  | Character. The .rds decisions file, one per site. |
| before | no | NULL | Optional data frame: the table the gadget was opened on (flag_habitat_inconsistencies()'s output). When supplied, a point's habitat is recorded as a reviewer REASSIGNMENT only where it differs from before; otherwise the habitat is treated as the automatic assignment of the day and is NOT frozen for later runs. Without before, this function cannot tell an automatic habitat from a reviewer reassignment at all: every non-NA main_habitat in reviewed is recorded as a reassignment (the conservative reading) and will be re-applied VERBATIM by apply_spatial_review_decisions on every later run -- freezing that point's habitat at whatever the automatic classifier happened to say the day it was reviewed, even if the classifier's own logic later changes for the better. Pass before whenever the pre-review table is available to avoid this. Matched on (point_id, taxon_name) when before carries taxon_col too, otherwise on point_id alone. |
| point_id_col | no | "point_id" | Column names. Defaults match review_spatial_flags()'s output. |
| flag_col | no | "spatial_flag" | Column names. Defaults match review_spatial_flags()'s output. |
| habitat_col | no | "main_habitat" | Column names. Defaults match review_spatial_flags()'s output. |
| taxon_col | no | "taxon_name" | Character. Name of the taxon column in reviewed (and, if present, before). Default "taxon_name". Absent from reviewed, every saved decision's taxon_name is NA -- see Details. |

**Value:** Invisibly, the merged decisions table ('point_id', 'taxon_name', 'spatial_flag', 'main_habitat', 'habitat_reassigned', 'decided_at').

#### Why the key includes taxon_name

point_id identifies a coordinate, not an occurrence record -- it is routine for several taxa to share one in an eDNA occurrence table (a gull and a fish detected at the same sampling point). Keying decisions on point_id alone means two taxa at the same point can carry genuinely different spatial_flag/main_habitat values, and a decision saved for one would silently overwrite the file's only record for that point -- discarding whichever taxon's row was not kept. Decisions are therefore keyed on (point_id, taxon_name). When reviewed has no taxon_col column, every decision's taxon_name is recorded as NA (an old-format, point-level decision); see apply_spatial_review_decisions for how such a decision is applied safely.

### taxahabitat_clear_cache(cache_dir = tools::R_user_dir("TaxaHabitat", "cache"), older_than_days = NULL, dry_run = FALSE, force = FALSE)

Report and clear TaxaHabitat's on-disk habitat-verdict cache

Lists, and optionally deletes, the per-taxon files written by 'build_habitat_lookup()' when it is given a 'cache_dir'. Entries have no built-in expiry - a verdict stays valid until the scheme, covariates, context, or 'cache_tag' change, which changes its key and makes it a miss anyway - so pruning is about disk usage and about deliberately forcing a fresh classification, not about correctness.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaHabitat", "cache") | Character. The directory passed to build_habitat_lookup()'s cache_dir. Defaults to tools::R_user_dir("TaxaHabitat", "cache"), matching the sibling packages; workflows that pass a project-local directory should pass the same one here. |
| older_than_days | no | NULL | Optional numeric. Delete only entries older than this many days. NULL (default) considers every entry. |
| dry_run | no | FALSE | Logical. TRUE reports what would be deleted without deleting it. |
| force | no | FALSE | Logical (default FALSE). Pass TRUE to clear a cache_dir that holds file(s) matching none of the recognized cache patterns -- see TaxaTools::list_cache_files(). |

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

