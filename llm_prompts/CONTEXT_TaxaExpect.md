# CONTEXT: TaxaExpect

**Estimate Bayesian Priors for Species Occurrence Using GBIF Data**

Generates theta priors (occupancy x detectability) for taxonomic assignment from occurrence data (see TaxaFetch). Occurrence data are first summarized at the grid level. At this scale, the user is able to apply spatial models that generate estimates of theta along with expected error. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-15 11:58:44 UTC; unix). 15 exported function(s).

## Functions

### apply_undetected_evidence(taxaexpect_priors, model_obj, evidence, grid_id, main_habitat = NULL, taxonomy = NULL, pricing = c("blend", "curve"), sampling_group = NULL, group_fallback = c("pooled_qualifying", "error", "skip"), min_group_n_eff = 100, min_group_f1 = 1L)

Elevate the dark-diversity floor prior for species with external occurrence-plausibility evidence

'generate_undetected_diversity' treats every species with zero occurrence records identically - the generic global-floor 'Beta(1, N_total - 1)', regardless of whether it has never been recorded within a thousand kilometers, or has real external evidence (a documented invasion-front species, a corroborated nearby record just outside the study bbox) making it a materially more plausible detection. This function is the single, shared mechanism for elevating that floor for named species, given evidence from any number of independent sources - designed so multiple sources can be combined safely wit

| Param | Required | Default | Doc |
|---|---|---|---|
| taxaexpect_priors | yes |  | Data frame. Must already contain the undetected_type == "global_floor" row from generate_undetected_diversity (errors if absent). Used both as the source of the floor/singleton anchors and to determine which evidence taxa are already observed. |
| model_obj | yes |  | A biofreq_model object, used only for meta$habitat_col (to determine whether main_habitat is required) so output rows sit on the same schema as every other prior-generating function in this package. |
| evidence | yes |  | Data frame (typically the row-bound output of one or more evidence-generating functions, e.g. generate_invasive_watch_evidence). Required columns: taxon_name (character), weight (numeric, 0-1 -- the source's probability of local presence), source (character, for audit only). Optional: p_conc (numeric, > 0; default 1) -- how much weight the presence claim carries against future evidence, in pseudo-observations. n_eff is retired (errors with migration guidance): the Beta concentration is now moment-matched, not supplied. Additional source-specific columns are ignored by this function. |
| grid_id | yes |  | Character. Single grid cell identifier this call applies to -- required, no default (mirrors generate_domestic_food_priors's single-site-per-call convention; a multi-site study calls this once per site). TaxaAssign::join_priors()'s primary join requires an exact grid_id match, so the output rows are only usable for observations at this specific site. |
| main_habitat | no | NULL | Character. Single habitat category this call applies to. Required (no default) when model_obj was trained with a non-NULL habitat_col; must be omitted (NULL, the default) when model_obj was trained with habitat_col = NULL. There is no habitat-agnostic option here, unlike generate_domestic_food_priors()'s main_habitat = NA rows (which join_priors() now has a dedicated fallback tier for) -- occurrence-plausibility evidence is deliberately habitat-AWARE, since a freshwater species found nearby is only locally plausible in a freshwater habitat, a real constraint that domestic/food contamination risk does not share. |
| taxonomy | no | NULL | Optional data frame with columns taxon_name and any subset of genus, family, order, class, phylum, joined onto the result the same way generate_undetected_diversity(taxonomy = ...) does. Default NULL. |
| pricing | no | c("blend", "curve") | "blend" (default, the original floor-additive presence mixture: theta = floor + w*(ceiling - floor)) or "curve" (unobserved-taxa redesign, 2026-08-31: theta = w * theta_present with theta_present = missing_mass / f1 from the kernel fit -- the mean theta of the neighborhood's own observed singletons -- and theta_absent = 0). theta_present was priced from missing_mass / chao_missing before 2026-09-05 (open decision #1, resolved): that made the branch's evidence total close exactly against chao_missing (sum(w) = chao_missing), but inherited chao_missing's own radius-instability (4x-21x on real data, driven by dividing by a doubleton count that sits in the single digits). chao_missing remains available on the kernel fit as a separate, reported-not-enforced budget AUDIT figure (sum(w) vs chao_missing -- an estimate of the total unseen-species count, not the price); it no longer feeds the price itself, and sum(w) is no longer expected to equal it exactly. Curve pricing removes the floor term that dominated every blended row. Requires a taxaexpect_kernel_priors model_obj with a finite theta_present (at least one neighborhood singleton), or -- since 2026-09-04 -- a multi-group fit, in which case each taxon is priced by its OWN sampling group's budget (see Per-group curve pricing). |
| sampling_group | no | NULL | Which sampling group each evidence taxon belongs to. Required (and only meaningful) when model_obj was fitted with sampling_group_col and pricing = "curve". Accepts a single group name (the whole evidence list shares one detection process -- the common case, e.g. an all-fish invasive-watch list), a named character vector (taxon -> group), or a data frame with taxon_name and sampling_group columns. A sampling_group column on evidence itself takes precedence. Deliberately NEVER inferred from taxonomy: the classification that produced the occurrence pool's groups lives in the caller's workflow, and a wrong group mis-prices silently rather than failing. |
| group_fallback | no | c("pooled_qualifying", "error", "skip") | What to do with an evidence taxon whose group fails the pricing guards. "pooled_qualifying" (default) prices it at the qualifying groups' combined budget and says so, per row, in pricing_basis; "error" refuses; "skip" drops those taxa with a message. Ignored for single-group fits. |
| min_group_n_eff | no | 100 | Support a sampling group must have before its own budget is trusted: at least this many effective records (default 100) and this many neighborhood singletons (default 1). Ignored for single-group fits. |
| min_group_f1 | no | 1L | Support a sampling group must have before its own budget is trusted: at least this many effective records (default 100) and this many neighborhood singletons (default 1). Ignored for single-group fits. |

**Value:** A tibble with one row per eligible taxon named in 'evidence': taxon_name The real taxon name. taxon_name_rank Always '"species"' - required for the row to match 'TaxaAssign::join_priors()''s composite join key. grid_id, main_habitat As supplied ('main_habitat' omitted entirely when 'model_obj' has no habitat concept). alpha, beta Beta(alpha, beta) prior parameters. theta_mean, theta_sd Derived fro

### calibrate_kernel_bandwidth(occurrence_data, site_habitat, lambda_grid = c(10, 25, 50, 100, 200), m_grid = 1, covariate_col = NULL, lambda_covariate_grid = NULL, lambda_latitude_grid = NULL, block_size_deg = 0.5, min_block_records = 20L, smoothing = 0.5, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat")

Calibrate kernel bandwidths by leave-one-block-out composition prediction

Chooses 'lambda_km' (and optionally the covariate bandwidth and the back-off mass 'm') for 'estimate_kernel_priors()' empirically: records are partitioned into spatial blocks; each block's species composition is predicted from all records _outside_ it, using the same kernel machinery evaluated at the block's own data centroid; predictions are scored by per-record multinomial log-loss against the block's actual records. Two reference predictors are always scored alongside for context: 'regional' (all held-out records, unweighted - "is locality worth anything?") and 'nearest_block' (the single n

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | As in estimate_kernel_priors(). |
| site_habitat | yes |  | As in estimate_kernel_priors(). |
| lambda_grid | no | c(10, 25, 50, 100, 200) | Numeric vector of candidate geographic bandwidths (km). Default c(10, 25, 50, 100, 200). |
| m_grid | no | 1 | Numeric vector of candidate back-off masses. Default 1 (calibrate lambda only). Supply several values to tune m jointly. |
| covariate_col | no | NULL | Optional: a numeric record column (e.g. depth) and candidate bandwidths for its kernel factor. When supplied, every (lambda, lambda_covariate, m) combination is scored; the block's mean covariate value stands in for the "site" value. NULL (default) disables the covariate factor. |
| lambda_covariate_grid | no | NULL | Optional: a numeric record column (e.g. depth) and candidate bandwidths for its kernel factor. When supplied, every (lambda, lambda_covariate, m) combination is scored; the block's mean covariate value stands in for the "site" value. NULL (default) disables the covariate factor. |
| lambda_latitude_grid | no | NULL | Optional numeric vector: candidate bandwidths (km) for estimate_kernel_priors()'s climate-similarity factor on the absolute-latitude difference. Inf (factor off) is always added to the sweep so the no-factor case competes on equal footing -- a best row with lambda_latitude = Inf means the data rejected the factor. NULL (default) omits the dimension entirely. |
| block_size_deg | no | 0.5 | Numeric scalar: CV block size in degrees (default 0.5). A block enters scoring only if it holds at least min_block_records records. |
| min_block_records | no | 20L | Integer, default 20L. |
| smoothing | no | 0.5 | Laplace pseudo-count added to every species when forming a predicted composition, so held-out species never score -Inf (default 0.5). |
| taxon_col | no | "taxon_name" | As in estimate_kernel_priors(). |
| lat_col | no | "decimalLatitude" | As in estimate_kernel_priors(). |
| lon_col | no | "decimalLongitude" | As in estimate_kernel_priors(). |
| habitat_col | no | "main_habitat" | As in estimate_kernel_priors(). |

**Value:** A list with results Data frame: one row per parameter combination plus the 'regional' and 'nearest_block' references; columns 'lambda_km', 'lambda_covariate', 'lambda_latitude', 'm', 'mean_logloss' (simple mean over blocks), 'weighted_logloss' (record-weighted), 'blocks_beating_nearest'. best The row minimizing 'weighted_logloss' among kernel rows. n_blocks Number of scored blocks.

### condition_evidence_on_habitat(evidence, habitat_lookup, site_habitat, w_floor = 0, verbose = TRUE)

Condition Presence Evidence on the Site Habitat

Multiplies each evidence row's presence weight by the taxon's own weight for the site habitat, floored at the weight a taxon with no evidence at all receives. Applied to the output of 'generate_regional_proximity_evidence', 'generate_presence_curve_evidence' and 'generate_inat_range_evidence' BEFORE 'apply_undetected_evidence' prices the rows.

| Param | Required | Default | Doc |
|---|---|---|---|
| evidence | yes |  | Data frame with taxon_name and weight columns (any evidence generator's output). |
| habitat_lookup | yes |  | Data frame from TaxaHabitat::build_habitat_lookup(): taxon_name plus one numeric weight column per habitat class. |
| site_habitat | yes |  | Character scalar naming the site's habitat column in habitat_lookup. |
| w_floor | no | 0 | Numeric in [0, 1). The weight below which no evidence row may fall -- pass the run's clamp weight (w_scale * exp(-d_cap / d_half) under curve pricing). Default 0. |
| verbose | no | TRUE | Logical. Report counts. Default TRUE. |

**Value:** 'evidence' with 'weight' replaced by the conditioned weight and three added columns: 'habitat_weight' (H_{site}, 'NA' when unknown), 'weight_unconditioned' (the generator's original weight) and 'habitat_floored' ('TRUE' where the product fell below 'w_floor').

### estimate_kernel_priors(occurrence_data, site_lat, site_lon, site_habitat, lambda_km, m = 1, covariate_col = NULL, site_covariate = NULL, lambda_covariate = NULL, lambda_latitude = NULL, site_id = NULL, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", sampling_group_col = NULL, support_weight = exp(-3))

Estimate site priors by distance-kernel weighting of occurrence records

Computes each species' expected share of legitimate detections at a sampling site ('theta') directly from habitat-stratified occurrence records, weighting every record by its distance to the site:

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | Data frame of cleaned, habitat-labelled occurrence records (one row per record). |
| site_lat | yes |  | Numeric scalars. The sampling site coordinates. |
| site_lon | yes |  | Numeric scalars. The sampling site coordinates. |
| site_habitat | yes |  | Character scalar. Focal habitat; records are stratified to habitat_col == site_habitat before any weighting. |
| lambda_km | yes |  | Numeric scalar. Geographic kernel bandwidth in km. Required, no default: the defensible value is dataset-specific -- derive it with calibrate_kernel_bandwidth() (leave-one-block-out composition prediction) rather than guessing. |
| m | no | 1 | Numeric scalar >= 0. Regional pseudo-records for the Dirichlet back-off (default 1, a weakly-informative single pseudo-record; tunable via calibrate_kernel_bandwidth()). m = 0 disables shrinkage. |
| covariate_col | no | NULL | Optional character. Name of a SINGLE numeric record column (e.g. "depth_m") for the product kernel -- accepts one scalar column name only. A second covariate (e.g. time) is not supported by the product kernel as written; adding one would require a second lambda_*/site_* pair and a genuine multi-factor product, not just a longer vector here. NULL (default) disables it. |
| site_covariate | no | NULL | Numeric scalar. The site's own value of covariate_col. Required when covariate_col is supplied. |
| lambda_covariate | no | NULL | Numeric scalar. Covariate kernel bandwidth, in the covariate's own units. Required when covariate_col is supplied. Records with NA covariate values receive the neutral weight 1 for the covariate factor (distance factor still applies) rather than being dropped. |
| lambda_latitude | no | NULL | Optional numeric scalar. Bandwidth (km) for a climate-similarity factor exp(-111 * \|\|lat\| - \|site_lat\|\| / lambda_latitude) on the ABSOLUTE latitude difference -- records from the site's own climate band (same \|latitude\|, either hemisphere) keep full weight while records poleward/equatorward of it decay, making north-south kilometers cost more than east-west kilometers. NULL (default) disables the factor. Tunable via calibrate_kernel_bandwidth()'s lambda_latitude_grid. |
| site_id | no | NULL | Character scalar. Identifier stamped on the output rows' grid_id column (kept under that name for downstream join compatibility; the value is treated as opaque everywhere downstream). Default: "Site_<lat>_<lon>". |
| taxon_col | no | "taxon_name" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| lat_col | no | "decimalLatitude" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| lon_col | no | "decimalLongitude" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| habitat_col | no | "main_habitat" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| sampling_group_col | no | NULL | Optional column naming a detection-process grouping (e.g. "sampling_group"). Default NULL: all taxa share one composition and one Good-Turing budget. This default is not a safe "do nothing" choice: with no sampling_group_col, every record is pooled regardless of detection process, with no warning or error, even when that means silently mixing genuinely incompatible processes (e.g. phytoplankton cell counts with bird point counts). Grouping is never inferred automatically from taxonomy or data -- this function has no way to know which taxa were sampled by a comparable process, so it never guesses. Supplying a correct sampling_group_col is the caller's responsibility, built BY HAND from real knowledge of detection methodology -- there is no automated way to detect "comparable method" from taxonomy or data alone (an LLM guess is not a substitute for real methodological knowledge either). This is not a burdensome ask: this function does NOT require pre-merged, sample-size-adequate groups for statistical adequacy -- it degrades gracefully, producing honestly wide uncertainty for a sparse group on its own (empirically confirmed on a real 9-group expert classification down to a single-taxon group, see README.md's "Shared detection effort" section) -- so classify at whatever granularity genuinely reflects distinct detection methods, without worrying whether each resulting group individually "has enough data." When supplied, theta AND the budget (f1, f2, missing_mass, chao_missing, theta_present) are computed WITHIN each group, because both are shared-denominator quantities that assume a common detection process. Pooling across processes dilutes a detectable taxon's share with records the assay could never amplify, and lets barely-sampled groups contribute singletons that inflate f1 -- and so chao_missing, quadratically -- while adding almost nothing to missing_mass, deflating theta_present (theta_present is priced from missing_mass / f1, so a diluted missing_mass still deflates it even though chao_missing no longer sits in that formula). Note this is a no-op for a taxonomically homogeneous pool (a fish assay whose occurrence pool is all fish), which is why it changes nothing at sites like GreatLakes; it matters for broad markers (18S) spanning groups with very different detection probabilities. With more than one group the pooled scalars are NA by design and $budget is authoritative -- a single number would be silently wrong. |
| support_weight | no | exp(-3) | Numeric in (0, 1]. A record counts toward the discrete neighborhood-support statistics (singleton detection, record counts) when its total kernel weight is at least support_weight (default exp(-3), i.e. within ~3 bandwidths). Continuous quantities (theta, n_eff) always use all records. |

**Value:** An object of class '"taxaexpect_kernel_priors"': a list with priors Data frame: 'taxon_name', 'grid_id', 'main_habitat', 'alpha', 'beta', 'theta_mean', 'theta_sd', 'prior_branch', 'effective_records'. n_eff Kish effective sample size at the site. W Total kernel weight. singletons Data frame of neighborhood singletons (species with exactly one supporting record): 'taxon_name', record 'lat'/'lon', '

### fit_regional_presence_curve(presence_df, bins = c(0, 100, 200, 400, 700, 1100))

Fit a distance-to-presence curve for regional-proximity weights

The per-dataset, self-calibrating alternative (2026-08-26 mixture redesign, D5) to accepting 'generate_regional_proximity_evidence''s default 'w_scale'/'d_half': estimate P(locally present | nearest external record at distance d) from a study's own data and read the two parameters off the fit.

| Param | Required | Default | Doc |
|---|---|---|---|
| presence_df | yes |  | Data frame with columns present (logical) and distance_km (numeric > 0): one row per species in the chosen recipe's population. |
| bins | no | c(0, 100, 200, 400, 700, 1100) | Numeric vector of distance-bin edges for the zero-positive bound table (and a fit-vs-binned diagnostic otherwise). Default c(0, 100, 200, 400, 700, 1100). |

**Value:** A list: w_scale, d_half Fitted parameters (NA when unidentifiable). fit The glm object (or NULL). identifiable FALSE when zero positives (or a degenerate fit). bin_table Per-bin n, positives, and Jeffreys 95 percent upper bound on P(present); plus a pooled row. n, n_present Sample sizes.

### generate_domestic_food_priors(model_obj, lat, lng, grid_id = NA_character_, domestic_animal_taxa = .default_domestic_animal_taxa, food_species_taxa = .default_food_species_taxa, known_cultivar_taxa = .default_known_cultivar_taxa, candidate_plant_taxa = NULL, match_list_taxa = NULL, taxaexpect_priors = NULL, radius_km = 50, ess = 5, max_ess = 50, taxonomy = NULL, api_token = Sys.getenv("INAT_API_TOKEN"), verbose = FALSE)

Generate priors for domestic, commensal, and food-associated species

Constructs Beta(alpha, beta) prior rows for named domestic/commensal animal species, human food/crop species, and (optionally) candidate cultivated/ornamental plants - the three-channel design from 'ecosystem_docs/REENTRY_PROMPT_domestic_food_species_priors.md'. Unlike 'generate_undetected_diversity''s anonymous Tier 3 proxies, every row here carries a real 'taxon_name' and a 'prior_source_type' category for downstream systematic handling (reporting, exclusion from biodiversity summaries, routing to review).

| Param | Required | Default | Doc |
|---|---|---|---|
| model_obj | yes |  | A biofreq_model object (output of train_biodiversity_model()), used only for its N_total and meta$habitat_col so these rows sit on the same theta scale as generate_undetected_diversity()'s output. |
| lat | yes |  | Numeric. Query site coordinates for the iNaturalist search. |
| lng | yes |  | Numeric. Query site coordinates for the iNaturalist search. |
| grid_id | no | NA_character_ | Character. Grid cell identifier to attach to every row (for joining into taxaexpect_priors). Default NA_character_. |
| domestic_animal_taxa | no | .default_domestic_animal_taxa | Character vector of domestic/commensal animal taxon names. Default .default_domestic_animal_taxa (a starting list -- extend for your study system). Set to character(0) to disable this channel. Normalized via TaxaTools::clean_taxon_names() before use -- see @section Name normalization. |
| food_species_taxa | no | .default_food_species_taxa | Character vector of food/crop species taxon names. Default .default_food_species_taxa. Set to character(0) to disable this channel. Normalized the same way as domestic_animal_taxa. |
| known_cultivar_taxa | no | .default_known_cultivar_taxa | Character vector of known cultivated/ornamental (non-food) plant taxon names. Default .default_known_cultivar_taxa. Set to character(0) to disable this channel. Normalized the same way as domestic_animal_taxa. Patched immediately like the two fixed lists above -- see @section Four fixed-list channels. |
| candidate_plant_taxa | no | NULL | Character vector of candidate plant-kingdom taxon names to check for real local cultivated/casual-grade iNaturalist evidence. Default NULL (channel disabled -- no live iNaturalist calls are made unless you supply candidates here, or unless match_list_taxa produces open-discovery candidates). Normalized the same way as domestic_animal_taxa. |
| match_list_taxa | no | NULL | Optional character vector of taxa that actually have a likelihood in this run (e.g. from match_obj/ lik_result). Default NULL (no gating -- every fixed-list channel is checked in full, the original behavior). See @section Match-list gating. |
| taxaexpect_priors | no | NULL | Optional data frame (or just its taxon_name column) of already-modelled priors, used only to shrink the open-discovery residual pool when match_list_taxa is supplied -- a match-list taxon with a real named row here doesn't need an iNaturalist check. Default NULL (residual pool is a safe superset, not incorrect, just less minimal). |
| radius_km | no | 50 | Numeric. iNaturalist search radius, in kilometers. Default 50. |
| ess | no | 5 | Numeric. Baseline effective sample size (in the same N_total units as generate_undetected_diversity()'s singleton_ess) assumed for domestic_animal_taxa/ food_species_taxa even with zero local iNaturalist evidence -- these categories are plausible almost anywhere. Default 5. |
| max_ess | no | 50 | Numeric. Cap on the evidence-boosted effective sample size, so a very large local iNaturalist count cannot dominate N_total. Default 50. |
| taxonomy | no | NULL | Optional data frame with columns taxon_name and any subset of genus, family, order, class, phylum, joined onto the result the same way generate_undetected_diversity(taxonomy = ...) does. Default NULL. When a kingdom column is also present, it additionally enables the iNaturalist kingdom cross-check (see inat_kingdom_mismatch in @return) -- without it, a mismatched-homonym result cannot be detected and is trusted as-is. When a phylum column is present AND match_list_taxa is supplied, it additionally enables the open-discovery residual step (see @section Match-list gating) -- without it, that step is skipped with a message. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. iNaturalist API token, forwarded to TaxaFetch::fetch_inat_occurrences(). Defaults to the INAT_API_TOKEN environment variable. |
| verbose | no | FALSE | Logical. Print progress. Default FALSE. |

**Value:** A tibble with one row per resolved domestic/food/plant taxon: taxon_name The real taxon name (never NA, unlike 'generate_undetected_diversity()''s anonymous proxies). taxon_name_rank Always '"species"' - every candidate channel here resolves to a real species-level name. Required for 'TaxaAssign::join_priors()''s composite-key join to ever match these rows at all (a previously-real gap: this colum

### generate_inat_range_evidence(inat_range, weight = 0.8, p_conc = 1, n_obs_threshold = 500L, require_name_match = TRUE)

Evidence rows for species inside their iNaturalist range polygon

The third evidence generator for 'apply_undetected_evidence' (2026-08-26 mixture redesign, D6), alongside 'generate_invasive_watch_evidence' and 'generate_regional_proximity_evidence'. Converts 'TaxaFetch::check_inat_range()' output into presence-probability evidence, replacing 'TaxaAssign::adjust_inat_range_priors()''s post-join binary elevation for the mixture pathway - so iNat evidence shares the same anchors, moment-matched concentration, and multi-source probabilistic-OR combination as every other evidence channel, instead of jumping rows straight to the singleton level outside the framew

| Param | Required | Default | Doc |
|---|---|---|---|
| inat_range | yes |  | Data frame from TaxaFetch::check_inat_range(). |
| weight | no | 0.8 | Numeric, 0-1. P(locally present) for an in-range, well-observed, name-verified species. Default 0.8. |
| p_conc | no | 1 | Numeric > 0. Presence-claim confidence in pseudo-observations (drives the confirmation update, not the static prior -- see apply_undetected_evidence). Default 1. |
| n_obs_threshold | no | 500L | Integer. Minimum n_observations for the range polygon to count as well-observed. Default 500L, matching TaxaAssign::adjust_inat_range_priors()'s established value. |
| require_name_match | no | TRUE | Logical. Exclude rows whose resolved iNat name differs from the query (or cannot be verified). Default TRUE; set FALSE only with a reviewed name mapping in hand. |

**Value:** Evidence tibble ('taxon_name', 'weight', 'p_conc', 'source = "inat_range"'), ready to 'dplyr::bind_rows()' with other generators' output and feed to 'apply_undetected_evidence'. Zero rows when nothing qualifies.

### generate_invasive_watch_evidence(invasive_taxa, weight, p_conc = 1, match_list_taxa = NULL)

Evidence rows for a user-supplied invasive/nonindigenous watch list

A thin evidence generator for 'apply_undetected_evidence': given a plain, user-supplied list of taxa (e.g. hand-pulled from the USGS Nonindigenous Aquatic Species database, or any other invasion-biology source relevant to your study), produces one evidence row per listed taxon with a flat, caller-chosen weight and confidence. Deliberately does no live querying, no geography/watershed reasoning, and no Beta-parameter math - see 'apply_undetected_evidence' for why that split exists and where the actual prior construction happens.

| Param | Required | Default | Doc |
|---|---|---|---|
| invasive_taxa | yes |  | Character vector of taxon names. Required, no default. |
| weight | yes |  | Numeric, 0-1. How strongly this list's membership should pull an unobserved taxon's prior toward the singleton-mirror ceiling -- see apply_undetected_evidence's How the elevation works section for the exact blend. Required, no default: there is no universally defensible value (an invasion risk you're highly confident about locally warrants a different weight than a precautionary watch-list entry, and this function has no way to know which is which for your study). |
| p_conc | no | 1 | Numeric, > 0. How much weight the presence claim carries against future evidence (the confirmation update), in pseudo-observations. Default 1 -- a curated listing counts as roughly one direct observation about presence. Does NOT affect the static prior's mean or concentration (both now derive from weight via apply_undetected_evidence's presence-mixture moment matching -- the former n_eff knob is retired). |
| match_list_taxa | no | NULL | Optional character vector of taxa that actually have a likelihood this run (e.g. unique(match_obj$taxon_name)). When supplied, invasive_taxa is restricted to the intersection -- avoids emitting evidence for list members that were never even candidates this run. Default NULL (no restriction). |

**Value:** A tibble with one row per taxon in scope: 'taxon_name', 'weight', 'p_conc', 'source' (always '"invasive_watch"'). Matches the evidence-table schema 'apply_undetected_evidence' expects. Empty tibble (correct schema, zero rows) when nothing is in scope.

### generate_presence_curve_evidence(taxon_names, w_scale, distance_km = NULL, d_half = 150, d_cap = 1000, k = 1, p_conc = 1, source = NULL)

Price unobserved candidates on the presence-distance curve

Emits an evidence frame (for 'apply_undetected_evidence()') pricing each taxon's presence probability from the shared distance curve

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of candidate species names. |
| w_scale | yes |  | Numeric scalar in (0, 1]. The curve's ceiling: presence probability for a species with a record at the site itself. Required, no default -- calibrate against a local checklist (the GreatLakes value is 0.05; see the regional-proximity generator's calibration record). |
| distance_km | no | NULL | Optional numeric vector of distances (km), either named by taxon or positionally aligned with taxon_names. Missing/NA entries -- and the NULL default -- price at d_cap (the clamp). |
| d_half | no | 150 | Numeric scalar, the curve's e-folding half-distance in km (default 150, matching generate_regional_proximity_evidence()). |
| d_cap | no | 1000 | Numeric scalar, the instrument-cap distance in km beyond which the curve is flat (default 1000, the regional generator's own fetch-buffer cap). |
| k | no | 1 | Numeric scalar >= 1, the bandwidth stretch for listed invaders (default 1, no lift). |
| p_conc | no | 1 | Numeric scalar > 0 passed through to the applier (default 1). |
| source | no | NULL | Character scalar stamped on the rows (default "distance_clamp" when no distances are supplied, "presence_curve" otherwise). |

**Value:** A data frame with columns 'taxon_name', 'weight', 'p_conc', 'source', 'distance_km', 'k' - ready for 'apply_undetected_evidence()'.

### generate_regional_proximity_evidence(zero_bbox_taxa, lat, lng, d_half = 150, w_scale = 1, age_half = 15, tile_zoom = 6L, buffer_margin = 1.5, min_buffer_km = 50, max_buffer_km = 1000, near_lat_tolerance_deg = 6, near_occurrence_min_n = 3L, max_coord_uncertainty = 500, year_range = paste0("2000,", format(Sys.Date(), "%Y")), cache_dir = tools::R_user_dir("TaxaFetch", "cache"), tile_cache_dir = NULL, verbose = FALSE)

Evidence rows for species with a real GBIF record just outside the study bbox

A thin, two-stage evidence generator for 'apply_undetected_evidence': for each taxon with no in-bbox occurrence record, cheaply checks whether GBIF has ANY record nearby at all (Stage 1), and only pays for a real, quality-screened fetch to find the actual nearest record and its age for the taxa where that cheap check finds something (Stage 2). Implements 'ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md'.

| Param | Required | Default | Doc |
|---|---|---|---|
| zero_bbox_taxa | yes |  | Character vector of taxon names with no in-bbox occurrence record this run -- typically every named candidate absent from taxaexpect_priors entirely. Required, no default. |
| lat | yes |  | Numeric scalars. The study site's own coordinates (Stage 1 and Stage 2 both search around this point). |
| lng | yes |  | Numeric scalars. The study site's own coordinates (Stage 1 and Stage 2 both search around this point). |
| d_half | no | 150 | Numeric > 0. Distance (km) at which weight decays to half its maximum -- see Choosing d_half/age_half. Default 150. |
| w_scale | no | 1 | Numeric in (0, 1]. Near-boundary presence probability: weight = w_scale * exp(-distance_km / d_half), so w_scale is P(locally present) for a species whose nearest record sits just outside the study bbox but that has NO records inside it. The default 1 is almost certainly too high for any real study -- a species with zero in-bbox records is usually genuinely absent even when nearby records exist. Calibrate against a local expert checklist: the GreatLakes2023 test case found 0 of 110 zero-bbox candidates with records at 12-990 km on the site's 53-species checklist (Jeffreys 95 percent upper bounds: 0.107 for the under-100 km bin, 0.027 pooled), and adopted w_scale = 0.05 -- which also satisfies the dataset-independent ordering bound that an unobserved species should never veto a singleton-level observed native at likelihood parity (w below roughly 1/19). See ecosystem_docs/ REENTRY_PROMPT_undetected_evidence_mixture_redesign.md (D4/D5). |
| age_half | no | 15 | Numeric > 0. Record age (years) at which p_conc decays to half its fresh-record value of 1 -- see Choosing d_half/age_half. Default 15. |
| tile_zoom | no | 6L | Integer. Forwarded to TaxaFlag::check_gbif_tile_range(zoom = ) for Stage 1. Default 6L (roughly continental scale). |
| buffer_margin | no | 1.5 | Numeric > 1. Stage 2's fetch radius is Stage 1's own dist_nearest_occupied_km times this margin (tile-pixel distance is coarse, so the real nearest record may sit a bit further than the tile-resolution estimate) -- clamped to [min_buffer_km, max_buffer_km]. Default 1.5. |
| min_buffer_km | no | 50 | Numeric. Floor/ceiling on Stage 2's fetch radius, regardless of what Stage 1 reported. Defaults 50/ 1000. |
| max_buffer_km | no | 1000 | Numeric. Floor/ceiling on Stage 2's fetch radius, regardless of what Stage 1 reported. Defaults 50/ 1000. |
| near_lat_tolerance_deg | no | 6 | Numeric > 0. A second, complementary test to the nearest-point distance above: at least near_occurrence_min_n of a taxon's Stage-2-filtered records must fall within this many degrees of latitude of lat (proportional fallback when a taxon has fewer total filtered records than that -- see near_occurrence_min_n). Ported from build_invasive_candidates.R's own identically-named safeguard (ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md), built after a real GLANSIS benchmark comparison found the plain nearest- point test alone is precision-poor: several species passed it purely on the strength of ONE isolated occurrence record (a stray record, or a real but climatically-artificial thermal-discharge refugium) while the bulk of that species' real range sat many latitude degrees away -- climate-implausible warm-water species were the dominant real pattern. Latitude (not full geodesic distance) is used deliberately as a cheap climate-tolerance proxy -- thermal/seasonal regime tracks latitude far more than longitude for a fixed distance budget. Default 6 (~660km, matching build_invasive_candidates()'s own tuned value -- a tighter 3-degree pass there cost a real, well-documented invader whose established population sat ~5 degrees of latitude from the study site despite being part of one connected system). |
| near_occurrence_min_n | no | 3L | Integer >= 0. A taxon must have at least this many Stage-2-filtered records within near_lat_tolerance_deg of lat, IN ADDITION TO clearing the nearest-point/buffer test above. Default 3L (an absolute count, not a fraction of a taxon's total filtered records -- a fraction would unfairly penalize a taxon with a large occurrence footprint and reward one with only a handful of records). Taxa with FEWER total Stage-2-filtered records than this threshold get a proportional fallback instead of an impossible bar: ALL of their (few) records must fall within near_lat_tolerance_deg, rather than requiring an absolute count they structurally cannot reach -- the real motivating case (build_invasive_candidates()'s own) is a species with exactly 1 occurrence record, genuinely close, that a flat count-of-3 test would otherwise always reject regardless of proximity. Set to 0 or 1 to disable this test and fall back to the original nearest-point-only behavior. |
| max_coord_uncertainty | no | 500 | Numeric. Forwarded to TaxaFetch::filter_gbif_quality(). Default 500 (meters, matching that function's own default). |
| year_range | no | paste0("2000,", format(Sys.Date(), "%Y")) | Character ("YYYY,YYYY") or NULL. Forwarded to TaxaFetch::get_gbif_occurrences()'s Stage 2 fetch. Default: 2000 to the current year, the same window every other GBIF fetcher in this ecosystem defaults to. PASS THE STUDY'S OWN WINDOW (the same year_range the main occurrence fetch used) so regional evidence and resident priors are judged on the same record set. Until 2026-09-12 the default was NULL (all time) on the reasoning that record age is the signal the p_conc discount reads out -- but that discount only narrows a row's CONFIDENCE, never its weight: a 1929 preserved specimen of a captive siamang 74 km from Point Conception still lifted that species' prior 480x above the zero-record floor and turned an 82\ level call into a species call. NULL restores the all-time fetch. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Forwarded to the Stage 2 fetch for checkpointing. Default tools::R_user_dir("TaxaFetch", "cache"). |
| tile_cache_dir | no | NULL | Character or NULL (default). Forwarded straight through to Stage 1's TaxaFlag::check_gbif_tile_range( cache_dir = ) -- see that function's own Caching section for the exact key/no-expiry/age-reporting design. NULL (the default) disables Stage 1 caching entirely, matching every prior release of this function: every zero-record taxon re-pays a live GBIF tile fetch on every call, which is exactly the cost this parameter exists to remove on a repeat run against unchanged data (the 2026-09-13 PtConception run spent 43 minutes here across 256 taxa). When supplied, this function also emits one summary line when it finishes: how many Stage 1 verdicts were served from cache, how many were freshly fetched, and the age in days of the oldest cache hit actually used -- so staleness (there is no TTL; see check_gbif_tile_range()) is visible to the caller rather than silent. |
| verbose | no | FALSE | Logical. Print per-taxon Stage 1/Stage 2 progress. Default FALSE. |

**Value:** A tibble with one row per taxon that cleared both stages: 'taxon_name', 'weight', 'p_conc', 'source' (always '"regional_proximity"') - matches the evidence-table schema 'apply_undetected_evidence' expects - plus audit columns 'distance_km', 'record_year', 'age_years' ('NA' when the matched record had no usable year), 'tile_zoom_used'. Empty tibble (correct schema, zero rows) when nothing in 'zero_

### generate_undetected_diversity(model_obj, jeffreys_threshold = 2L, singleton_ess = 2L, taxonomy = NULL)

Generate Priors for Undetected Species

Constructs Beta(alpha, beta) prior objects for species that are plausibly present in the regional pool but were not recorded anywhere in the dataset (Tier 3 species). Two sources of priors are generated:

| Param | Required | Default | Doc |
|---|---|---|---|
| model_obj | yes |  | A biofreq_model object (output of train_biodiversity_model()) or a taxaexpect_kernel_priors object (output of estimate_kernel_priors() -- kernel-priors redesign): the same rules then run on kernel ingredients (N = Kish effective sample size, singletons = neighborhood singletons stamped with the site id). |
| jeffreys_threshold | no | 2L | Integer. If N_total is below this value, use a Jeffreys prior Beta(0.5, 0.5) for the global floor instead of Beta(1, N_total - 1). Default 2. |
| singleton_ess | no | 2L | Integer. Effective sample size used for moment-matching singleton mirror priors. Controls how tightly the prior is concentrated around the observed singleton theta: alpha = theta_obs * singleton_ess, beta = (1 - theta_obs) * singleton_ess. A small value (default 2) produces a diffuse prior appropriate for a species seen exactly once. |
| taxonomy | no | NULL | Optional data frame with columns taxon_name and any subset of genus, family, order, class, phylum. When supplied, singleton mirror rows are annotated with the full taxonomic hierarchy of their source_taxon_name via a left join on taxon_name. Typically built from occurrences_std (which carries the full GBIF hierarchy). Used by TaxaAssign::join_priors() for hierarchical dark diversity grouping (Issue 3). Global floor rows always receive NA for all taxonomy columns. Default NULL (taxonomy columns added as NA). |

**Value:** A tibble with one row per undetected species proxy, containing: taxon_name Always NA - proxies have no taxonomic identity. grid_id Grid cell identifier inherited from singleton source, or NA for the global floor. habitat Habitat inherited from singleton source, or NA for global floor. Column absent entirely when 'model_obj' was trained with 'habitat_col = NULL'. alpha Alpha parameter of Beta(alpha

### generate_user_specified_evidence(taxon_weights, p_conc = 1)

User-specified presence evidence for species of special concern

The explicit policy knob from the unobserved-taxa redesign: a user may assert a presence probability 'w' for particular species (raising a watch species' chance of _resolving_ in consensus - detection itself is already guaranteed prior-free by 'TaxaFlag::flag_watch_candidates()'). Rows carry 'source = "user_specified"' so the provenance survives into 'evidence_sources' and any downstream caveat can see it.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_weights | yes |  | Named numeric vector: names are species, values are presence probabilities in (0, 1]. |
| p_conc | no | 1 | Numeric scalar > 0 (default 1). |

**Value:** A data frame with columns 'taxon_name', 'weight', 'p_conc', 'source' - ready for 'apply_undetected_evidence()'.

### kernel_budget_sensitivity(fit, occurrence_data, support_weight_grid = exp(-(1:5)), lambda_grid = NULL, verbose = FALSE)

Sensitivity of a kernel Good-Turing budget to its counting radius

Re-computes the $budget of a fitted 'estimate_kernel_priors()' object across a grid of counting radii ('support_weight') and, optionally, geographic bandwidths ('lambda_km'), and summarizes how far each group's budget quantities move. Report this next to any 'chao_missing' or 'theta_present' figure you intend to act on.

| Param | Required | Default | Doc |
|---|---|---|---|
| fit | yes |  | A "taxaexpect_kernel_priors" object from estimate_kernel_priors(). |
| occurrence_data | yes |  | The same occurrence data fit was computed from. The fit does not retain the records, so they must be supplied again; passing different data silently answers a different question, and a mismatch at the fit's own settings is reported by $reproduces_fit. |
| support_weight_grid | no | exp(-(1:5)) | Numeric vector in (0, 1] of counting radii to sweep. Default exp(-(1:5)), i.e. 1 to 5 bandwidths, which brackets the exp(-3) default on both sides. |
| lambda_grid | no | NULL | Optional numeric vector of geographic bandwidths (km). NULL (default) sweeps only the counting radius, holding lambda_km at the fit's own value -- the cleaner diagnostic, since it moves one boundary and nothing else. Supply a grid to see the joint sensitivity. |
| verbose | no | FALSE | Logical. Message each setting as it is computed. |

**Value:** An object of class '"taxaexpect_kernel_budget_sensitivity"': a list with budget Long data frame, one row per (setting, sampling group): the $budget columns plus 'lambda_km', 'support_weight', 'radius_lambdas' ('-log(support_weight)') and 'radius_km'. summary One row per sampling group: the range of 'f1', 'f2', 'chao_missing' and 'theta_present' over the sweep, 'theta_present_spread' (max/min over 

### plot_theta_surface(kernel_fit, occurrence_data, taxon, n_grid = 256L, bbox = NULL, m = NULL, covariate_at = NULL, alpha_by_n_eff = TRUE, n_eff_floor = NULL, mask = NULL, site_marker_radius = 5, hover_labels = TRUE, interactive = FALSE, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", ...)

Evaluate the kernel-prior estimator on a spatial lattice (KDE prior field)

Computes the SAME distance-kernel estimator 'estimate_kernel_priors()' applies at one site, at every point of a regular lattice instead, via binned FFT convolution. The result is a genuine prior FIELD: evaluating the surface at the site's own coordinates reproduces 'estimate_kernel_priors()''s 'theta_mean' for the requested taxon exactly (to numerical/grid-discretization tolerance), because it is the identical formula, not a smoothed rendering of it.

| Param | Required | Default | Doc |
|---|---|---|---|
| kernel_fit | yes |  | A taxaexpect_kernel_priors object from estimate_kernel_priors() -- the source of lambda_km, m, lambda_latitude, covariate_col, lambda_covariate, site_habitat, and the site coordinates (site_lat/site_lon, marked on the map). Every tuning parameter defaults from this object so the surface cannot silently drift from the priors it claims to depict. |
| occurrence_data | yes |  | The SAME occurrence data frame passed to estimate_kernel_priors() to produce kernel_fit (cleaned, habitat-labelled occurrence records). |
| taxon | yes |  | Character vector of one or more species names to surface. Length 1 returns a single surface; length > 1 returns one surface per taxon (a facet grid for the static plot, a layer-toggle overlay for the interactive map). |
| n_grid | no | 256L | Integer, lattice resolution per side (default 256L). |
| bbox | no | NULL | Optional named numeric vector/list with lat_min, lat_max, lon_min, lon_max. Default NULL: computed from the full extent of the habitat-stratified records (unioned with the site coordinates) plus padding, which GUARANTEES every record that estimate_kernel_priors() would use is included in the lattice binning -- this is what makes the site-identity invariant hold. Supplying a smaller custom bbox excludes records outside it from the surface (a documented, deliberate window truncation), which can disagree with the exact site value if the site itself sits near or outside that window. |
| m | no | NULL | Optional back-off mass override. Default NULL: use kernel_fit$params$m (the value the priors were actually fit with). |
| covariate_at | no | NULL | Optional numeric scalar: the covariate value (e.g. depth) to hold fixed across the whole lattice. Default NULL: the covariate factor is omitted entirely and a message documents this (see @section Covariate and latitude factors). Only meaningful when kernel_fit was built with a covariate_col; supplying it against a fit that has none is an error (nothing to condition on). |
| alpha_by_n_eff | no | TRUE | Logical (default TRUE). Fade the surface toward transparent where lattice-point n_eff(x) is low relative to the surface's own maximum, so a reader cannot mistake a lightly-supported extrapolation for a well-evidenced estimate. |
| n_eff_floor | no | NULL | Optional numeric. Lattice points with n_eff(x) below this value are masked outright (drawn as background, not just faded), independent of alpha_by_n_eff. Default NULL: no outright mask. |
| mask | no | NULL | Optional geometry restricting the surface to a region of interest (a lake outline, a bay, a survey boundary). Cells whose centres fall outside become NA -- transparent on the map, and excluded from any summary of the returned matrices. Accepts a WKT POLYGON/ MULTIPOLYGON string -- including, directly, the same search polygon a workflow already passes to its GBIF fetch, which is usually what you want, since it clips the map to the geometry the records were fetched under -- or an sf/sfc polygon (requires the sf package), or a plain two-column lon/lat matrix/data frame, or a list of such matrices (a cell is kept if it falls inside ANY of them, for islands or multi-basin masks). Deliberately a parameter with no default: the correct mask is application-specific, so the package supplies none. |
| site_marker_radius | no | 5 | Numeric (default 5). Radius in pixels of the hollow circle marking the site on the interactive map. The marker is drawn unfilled and on top so it cannot hide the cell it marks (the default pin marker did, which is why this is small and hollow). |
| hover_labels | no | TRUE | Logical (default TRUE). Show theta and the local effective sample size on hover over each rendered cell of the interactive map. |
| interactive | no | FALSE | Logical (default FALSE). FALSE returns a static base-graphics plot. TRUE returns a Leaflet overlay (guarded by requireNamespace("leaflet")); leaflet is already in TaxaExpect's Suggests, so this adds no new dependency. |
| taxon_col | no | "taxon_name" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| lat_col | no | "decimalLatitude" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| lon_col | no | "decimalLongitude" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| habitat_col | no | "main_habitat" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| ... | yes |  | Passed to the static plot's underlying graphics::image() call (e.g. main) or, when interactive = TRUE, to leaflet::addRectangles(). |

**Value:** An object of class '"taxaexpect_theta_surface"': a list with surface A list with 'lat_grid', 'lon_grid' (lattice coordinates), 'theta' (an 'n_grid' x 'n_grid' matrix for one taxon, or a named list of such matrices for several), 'n_eff', 'W' (Kish effective sample size and total kernel weight at every lattice point), 'regional_composition' (the 'p_i' used per requested taxon), and 'params' (the res

### report_priors(priors_output, verbose = FALSE)

Generate a Report Section for Prior Estimation

Summarizes the prior estimation produced by TaxaExpect into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| priors_output | yes |  | Either: A list with a $priors element (contains $priors, $model, $occurrences, $grid_result) -- the shape produced by the archived build_priors() (GLMM chain, archived 2026-09-09, see archive_glmm_prior_pipeline/). Still accepted here so an OLD, already-computed build_priors() result cached on disk keeps working with this function. A data frame of priors directly -- the shape produced by estimate_kernel_priors (current recommended path) or, historically, the archived generate_full_priors(). |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing prior estimation approach. results Template text summarizing prior coverage. citations Propagated from occurrence data if available. params Named list of prior parameters. statistics Named list of summary counts.

## Quick Start

``` r
library(TaxaExpect)

# 1. Calibrate the kernel bandwidth (and regional back-off m) by
#    leave-one-block-out composition prediction -- never hand-set.
calib <- calibrate_kernel_bandwidth(
  occurrence_data = occurrences,   # habitat-labelled occurrence records
  site_habitat    = "Marine",
  lambda_grid     = c(10, 25, 50, 100, 200)   # km
)
lambda_km <- calib$best$lambda_km

# 2. Estimate kernel priors at your site (resident_observed rows)
kernel_fit <- estimate_kernel_priors(
  occurrence_data = occurrences,
  site_lat        = 34.45,
  site_lon        = -120.47,
  site_habitat    = "Marine",
  lambda_km       = lambda_km
)

# 3. Add resident_undetected rows (singleton mirrors + Good-Turing floor)
undetected <- generate_undetected_diversity(kernel_fit)

# 4. Assemble the prior table for TaxaAssign
priors <- dplyr::bind_rows(kernel_fit$priors, undetected)

# 5. Explore the prior field
plot_theta_surface(kernel_fit, occurrence_data = occurrences,
                    taxon = "Girella nigricans")
```

