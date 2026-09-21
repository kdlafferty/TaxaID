# CONTEXT: TaxaFlag

**Flag Anomalous Detections in Taxonomic Assignments**

Identifies and flags anomalous detections in taxonomic assignment results from biological surveys. Detects laboratory and field contamination by comparing read proportions against control samples, flags handler-related artifacts near equipment setup or collection events, and provides LLM-based expert review of habitat fit, geographic plausibility, contaminant risk, and taxonomic scope. Operates on consensus data frames and appends categorical flag columns for user-driven filtering. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-21 14:57:58 UTC; unix). 11 exported function(s).

## Functions

### add_posthoc_assessment(consensus_df, winner_likelihood_col = "winner_likelihood", consensus_taxon_col = "consensus_taxon", consensus_rank_col = "consensus_rank", likelihood_threshold = 0.5, domestic_taxa = NULL, domestic_prior_source = c("wild", "augmented"), primary_confusion_risk_col = "winner_own_rank_confusion_risk", consensus_confusion_risk_col = "consensus_confusion_risk", discriminating_threshold = 0.05, indistinguishable_threshold = 0.5, winner_theta_col = "winner_theta_mean", winner_record_col = "winner_has_occurrence_record", consensus_prior_col = "consensus_prior", consensus_record_col = "consensus_has_occurrence_record", expected_theta_threshold)

Add post-hoc plausibility and discrimination assessments to a consensus data frame

Appends two independent, orthogonal diagnostic axes to a 'TaxaAssign::posterior_consensus()' output, reported for 'primary_taxon' and 'consensus_taxon' separately: occurrence plausibility (Axis 1 - 'primary_plausibility'/ 'consensus_plausibility', "how expected is this taxon here?") and discrimination (Axis 2 - 'primary_discrimination'/ 'consensus_discrimination', "could the evidence tell this taxon apart from a plausible relative?"). Neither axis gates or overrides the other, and neither is folded into a single combined categorical - see '@section' below for both, and *Why no rank-based ...

| Param | Required | Default | Doc |
|---|---|---|---|
| consensus_df | yes |  | Data frame. Output of TaxaAssign::posterior_consensus(), containing at minimum winner_likelihood_col, consensus_taxon_col, and consensus_rank_col. |
| winner_likelihood_col | no | "winner_likelihood" | Character. Column in consensus_df holding the winner's ratio-normalised likelihood (default "winner_likelihood"). Used only by the domestic-species caveat (see below) -- a strong value here means the ID itself is trustworthy, independent of whether the occurrence prior underrepresents the taxon. |
| consensus_taxon_col | no | "consensus_taxon" | Character. Column holding the consensus taxon name (default "consensus_taxon"). Used only by the domestic-species caveat, to match against domestic_taxa. |
| consensus_rank_col | no | "consensus_rank" | Character. Column holding the consensus rank (default "consensus_rank"). Drives which expected_theta_threshold entry consensus_plausibility compares against. |
| likelihood_threshold | no | 0.5 | Numeric in (0, 1). Likelihood cutoff the domestic-species caveat uses for "the ID itself is trustworthy" (default 0.5). Below this, the winner had less than half the sequence-match density of the best-matching hypothesis. Unused when domestic_taxa is NULL. |
| domestic_taxa | no | NULL | Character vector or NULL (default). Taxon names (matched against consensus_taxon_col) that are domestic or synanthropic for your study system (e.g. "Felis catus", "Canis familiaris", "Bos taurus") -- there is no built-in default list, since what counts as "domestic" is study-system-specific. NULL disables this feature entirely (matches flag_handler's handler_taxa convention). See the Domestic/synanthropic species caveat section above. |
| domestic_prior_source | no | c("wild", "augmented") | Character. One of "wild" (default) or "augmented". "wild" assumes the underlying occurrence prior came from a raw occurrence database (GBIF/iNaturalist) with no domestic-species augmentation, so a strong-likelihood + low-plausibility domestic-species row is flagged via domestic_prior_caveat. "augmented" means the prior pipeline already incorporated known local domestic/synanthropic presence, so low occurrence plausibility is treated as informative and the flag never fires. Ignored when domestic_taxa is NULL. |
| primary_confusion_risk_col | no | "winner_own_rank_confusion_risk" | Character. Column in consensus_df holding TaxaAssign::posterior_consensus()'s winner_own_rank_confusion_risk -- the confusion-risk value rank-matched to primary_taxon's own resolved rank (default "winner_own_rank_confusion_risk"). Drives primary_discrimination. See @section Discrimination (Axis 2) below. |
| consensus_confusion_risk_col | no | "consensus_confusion_risk" | Character. Column holding the confusion-risk value rank-matched to consensus_taxon (default "consensus_confusion_risk"). Drives consensus_discrimination. |
| discriminating_threshold | no | 0.05 | Numeric in [0, 1] (default 0.05). Below this, the resolved rank is "discriminating". |
| indistinguishable_threshold | no | 0.5 | Numeric in [0, 1], >= discriminating_threshold (default 0.5). At or above this, the resolved rank is "indistinguishable"; between the two thresholds, "weak". |
| winner_theta_col | no | "winner_theta_mean" | Character. Column in consensus_df holding the winning hypothesis's own raw occurrence-model share (default "winner_theta_mean", from TaxaAssign::posterior_consensus()). Drives primary_plausibility. Deliberately reads theta_mean, NOT winner_prior/prior_mean -- see @section Occurrence plausibility below for why the two are not interchangeable. |
| winner_record_col | no | "winner_has_occurrence_record" | Character. Column indicating whether the winning hypothesis's taxon carries a real occurrence record at all (default "winner_has_occurrence_record"). This, NOT a low theta value, is what makes a call "unprecedented". |
| consensus_prior_col | no | "consensus_prior" | Character. Column holding the occurrence-model share (theta_mean-based group sum, see TaxaAssign::posterior_consensus()'s own docs) for the consensus taxon (default "consensus_prior"). |
| consensus_record_col | no | "consensus_has_occurrence_record" | Character. Column indicating whether the consensus taxon's group carries a real occurrence record at all (default "consensus_has_occurrence_record"). This, NOT consensus_prior_col's NA-ness, is what makes a call "unprecedented" at consensus scope -- consensus_prior is NA for two different reasons (no local member found, OR group_priors was never supplied to posterior_consensus() at all) that this column alone cannot distinguish; a taxon with NA here is "not_modeled", not "unprecedented". |
| expected_theta_threshold | yes |  | Named numeric vector, no default -- this genuinely depends on the taxon assemblage being scored and there is no universal safe value (mirrors TaxaAssign::join_priors()'s backbone_id / TaxaAssign::score_consensus()'s rank_thresholds, both required for the same reason). Names must be rank labels (e.g. c(species = ..., genus = ..., family = ...)); "species" is required, since primary_plausibility always compares against it (see @section Occurrence plausibility). A recorded taxon at or above the threshold for ITS OWN rank is "expected"; below it, "unexpected"; a rank with no entry in this vector gets "not_modeled" rather than an unsafe cross-rank comparison. Recommended: the median theta_sum at each rank from TaxaAssign::compute_group_priors() (species from median(taxaexpect_priors$theta_mean, na.rm = TRUE) directly, since compute_group_priors() is only built for genus/family) -- an "at least as expected as a typical local taxon at this rank" reading, avoiding a fitted or absolute cutoff. See @section Occurrence plausibility. If you derive it that way, the boundary FLOATS with the data. The recommendation above computes the threshold from the very table being classified, so it is a within-run RELATIVE judgement, not a fixed criterion, and two runs of the same site can classify differently with no code change and nothing wrong. Measured at GreatLakes: re-running only the prior side four days later refreshed 346 resident_undetected evidence rows (the priors were otherwise structurally identical -- same 483 rows, same 467 taxa, same branch counts), which moved median(theta_mean) from 1.72e-07 to 1.48e-08, an 11.7x shift in the species threshold, and unexpected went from 1 row to 18. The pipeline itself is deterministic: two runs on identical inputs produced byte-identical consensus rows. This is a property to REPORT, not a defect to patch. Wherever these categories are published, say what the threshold was and that it is assemblage-relative; a reader comparing unexpected counts across runs or sites is otherwise comparing two different questions. Pass a fixed vector instead if you need a criterion stable across runs -- at the cost of the "typical local taxon" reading that makes the data-derived version meaningful in the first place. |

**Value:** 'consensus_df' with five columns appended: 'primary_plausibility', 'consensus_plausibility' Character. Occurrence plausibility (Axis 1) of 'primary_taxon' and of 'consensus_taxon': '"expected"', '"unexpected"', '"unprecedented"', or '"not_modeled"' when nothing is computable - including when 'consensus_rank' has no matching entry in 'expected_theta_threshold'. 'NA' when the required source ...

### check_gbif_tile_range(taxon_key, query_lat, query_lon, zoom = 6L, buffer_px = 512L, escalate = TRUE, min_zoom = 0L, base_url = "https://api.gbif.org/v2/map/occurrence/density", cache_dir = NULL)

Spatial-isolation signal for a taxon from GBIF's occurrence-density map tiles

Downloads the GBIF occurrence-density PNG tile(s) covering a query point and a surrounding buffer, and reports how isolated that point is from the taxon's known range: whether the point itself falls in an occupied cell, the real-world distance to the nearest occupied cell, and the size of the occupied blob nearest the point (a weak proxy for "one lone report" vs. "a small cluster of independent reports").

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_key | yes |  | Integer. GBIF backbone usageKey for the taxon. Resolve via TaxaFetch::get_keys_from_context() or rgbif::name_backbone(). |
| query_lat | yes |  | Numeric scalars. The point to check. query_lat must be within Web Mercator's valid range (approximately -85.05 to 85.05 -- the projection is undefined at the poles). |
| query_lon | yes |  | Numeric scalars. The point to check. query_lat must be within Web Mercator's valid range (approximately -85.05 to 85.05 -- the projection is undefined at the poles). |
| zoom | no | 6L | Integer in [0, 12]. Starting tile zoom level. Controls both the real-world size of each density cell and how much ground a fixed buffer_px covers -- a coarser (smaller) zoom gives a wider, coarser view for the same download cost; a finer (larger) zoom gives tighter precision over a smaller area. Default 6L is roughly continental scale (tens to low hundreds of km per pixel, depending on latitude). |
| buffer_px | no | 512L | Integer. How far around the query point to scan for the nearest occupied cell, in tile pixels. Tiles are fetched in whole 512x512 blocks, so this is rounded up to the nearest multiple of 512. |
| escalate | no | TRUE | Logical. Widen the search to coarser zoom levels when nothing is found at zoom -- see "Zoom escalation" above. Default TRUE. |
| min_zoom | no | 0L | Integer in [0, zoom]. Coarsest zoom level escalation is allowed to reach. Default 0L (the whole world, one tile). Ignored when escalate = FALSE. |
| base_url | no | "https://api.gbif.org/v2/map/occurrence/density" | Character. GBIF map tile base URL. Exposed for testing. |
| cache_dir | no | NULL | Character or NULL (default). Directory for a persistent, per-key on-disk cache -- see Caching below. NULL disables caching entirely. |

**Value:** A one-row data frame: taxon_key, query_lat, query_lon As supplied. zoom_requested The 'zoom' argument, as supplied. zoom_used The zoom level the reported values were actually computed at - 'zoom_requested' unless escalation stepped down to find something. 'NA' when 'escalate = TRUE' (the default) and nothing was found anywhere from 'zoom' down to 'min_zoom' (nothing was ever "used"). When ...

### compute_local_occurrence_distance(taxon_names, query_lat, query_lon, occurrence_data, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", date_col = NULL)

Distance from a query point to the nearest already-fetched GBIF occurrence

For each taxon in 'taxon_names', finds the nearest record of that taxon already present in 'occurrence_data' and reports the geodesic distance from 'query_lat'/'query_lon' to it. 'occurrence_data' is meant to be data a workflow already fetched for its own purposes (e.g. the 'all_occurrences'/'occurrences_clean' objects 'TaxaFetch' produces during the normal pipeline) - this function costs nothing beyond arithmetic, no new GBIF call, since that regional data is already in hand.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector. One or more taxon names to check (e.g. every consensus_taxon flagged "unexpected"/"unprecedented" in one review session). Matched exactly against occurrence_data[[taxon_col]]. |
| query_lat | yes |  | Numeric scalars. The point to measure distance from -- typically the study site's own centroid. |
| query_lon | yes |  | Numeric scalars. The point to measure distance from -- typically the study site's own centroid. |
| occurrence_data | yes |  | Data frame of already-fetched occurrence records (e.g. all_occurrences, occurrences_clean). Must contain taxon_col, lat_col, lon_col. |
| taxon_col | no | "taxon_name" | Character scalars. Column names in occurrence_data. Defaults match TaxaFetch's DarwinCore-aligned convention. |
| lat_col | no | "decimalLatitude" | Character scalars. Column names in occurrence_data. Defaults match TaxaFetch's DarwinCore-aligned convention. |
| lon_col | no | "decimalLongitude" | Character scalars. Column names in occurrence_data. Defaults match TaxaFetch's DarwinCore-aligned convention. |
| date_col | no | NULL | Character or NULL. Optional column in occurrence_data giving the nearest record's collection date/year (e.g. GBIF's own "year" standard column). When supplied and present, the matched nearest record's raw value is surfaced as nearest_date -- lets a caller weigh a fresh vs. a decades-old nearest record differently without a second lookup. Default NULL (no age column requested; nearest_date is simply absent from the output). No parsing/normalization is done on the raw value; a "year" column comes back as whatever numeric/character type it already was. |

**Value:** A data frame, one row per unique entry in 'taxon_names': taxon_name As supplied. n_local_records Count of 'occurrence_data' rows for this taxon with non-missing coordinates. '0' for a taxon with no local record at all - for a genuinely unprecedented taxon this IS the answer, not a failure to find one. dist_nearest_km Geodesic (great-circle) distance in km from the query point to the nearest ...

### flag_contaminant(input_df, event_col = "event_id", taxon_col = "taxon_name", count_col = "count", control_samples = NULL, sample_type_col = NULL, control_types = NULL, exclude_samples = NULL, contaminant_type = "lab_contaminant", score_thresholds = c(0.5, 0.9), prior_weight = 20, require_control_evidence = FALSE, site_col = NULL, min_sites_systemic = 2L, min_control_obs = 2L, verbose = TRUE)

Flag Potential Contaminants by Comparison to Control Samples

Compares detection proportions between field samples and control samples (negative controls or positive controls) to identify taxa that may be contaminants. Supports any labelled control samples (extraction, PCR, or field blanks; for non-sequence data, a blank photo/recording or a negative-control site) plus positive controls.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame in long format with at minimum columns for sample identification, taxon identification, and count data (e.g. read counts, detection counts). |
| event_col | no | "event_id" | Character. Column name identifying collection events (e.g., individual filters, bottles, or deployments). Default "event_id". |
| taxon_col | no | "taxon_name" | Character. Column name identifying taxa (species, ESV, ASV, etc.). Default "taxon_name". |
| count_col | no | "count" | Character. Column name with integer count data. Default "count". |
| control_samples | no | NULL | Character vector of sample IDs that are controls (negative controls or positive controls). Mutually exclusive with sample_type_col; at least one must be supplied. |
| sample_type_col | no | NULL | Character. Column name containing sample type labels. When supplied, control_types identifies which values are controls. Mutually exclusive with control_samples. |
| control_types | no | NULL | Character vector of values in sample_type_col that identify control samples. Required when sample_type_col is used. Default NULL. |
| exclude_samples | no | NULL | Character vector of sample IDs to exclude from both control and field calculations. Use to remove e.g. extraction controls when analysing PCR controls, or vice versa. Default NULL. |
| contaminant_type | no | "lab_contaminant" | Character. Label for the type of contamination being assessed, embedded in validity_flag's values (e.g. "invalid_lab_contaminant") -- see @return below. Does NOT change output column NAMES (see Details); those are fixed (observation_validity/validity_flag/ validity_reason) so every TaxaFlag flag_*() mechanism shares one schema. Common values: "lab_contaminant", "field_contaminant", "positive_control". Default "lab_contaminant". |
| score_thresholds | no | c(0.5, 0.9) | Numeric vector of length 2. Thresholds for converting observation_validity to validity_flag. Values at or below the first are "invalid_{contaminant_type}" (probable contaminant); at or below the second, "questionable_{contaminant_type}"; higher values are "valid" (likely a genuine detection). Default c(0.5, 0.9). |
| prior_weight | no | 20 | Numeric (default 20). Empirical Bayes shrinkage strength, in units of "equivalent reads" (see .compute_contaminant_scores()'s own documentation for why reads, not samples). Controls how strongly the final field-vs-control ratio is pulled toward 0.5 (maximally uncertain) when a taxon has little total read support overall. Higher values shrink harder (more conservative, less willing to call a thinly-supported taxon confidently clean or contaminated); 0 disables shrinkage entirely, restoring the raw depth-weighted ratio. |
| require_control_evidence | no | FALSE | Logical. When TRUE, an ESV that was never detected in ANY control is labelled "no_control_evidence" instead of being scored, and ESVs that ARE seen in a control are split by DIRECTION. Default FALSE, which emits a warning when it bites (see below); TRUE is the defensible setting for new work. Why: the shrunken score is driven by READ DEPTH when control detections are rare, so it assigns a contamination verdict to ESVs with no contamination evidence at all. Measured on a real 12S run: of 13,597 ESVs only 43 were ever detected in a single control, yet 10,300 were labelled questionable_lab_contaminant -- the whole middle tier had ZERO blank evidence, and the rate was 75-81% in every marker and workflow checked because it reflects the read-depth distribution rather than contamination. DIRECTION IS THE POINT. Contamination flows control -> sample; CARRYOVER flows sample -> control, which is what happens when a blank picks up a little of an abundant local taxon. The first must be filtered and the second must not, and a symmetric score cannot tell them apart. |
| site_col | no | NULL | Character or NULL. Column giving each event's site. When supplied, site breadth is computed per taxon and used as a DISCRIMINANT, not merely as extra power: a systemic contaminant (reagent, water supply) appears in controls at MANY sites regardless of which sites' samples carry it, whereas a local source appears in controls at the ONE site whose samples are full of it. This is what dissolves the pooling-versus-pairing dilemma -- pooling controls buys power but lets one trip's contamination speak for another's, while pairing by event buys specificity at the cost of power (on real data, event-paired controls emptied the invalid tier completely: 0 ESVs, against 43 and 323 in pooled runs). Using the cross-site PATTERN keeps both. |
| min_sites_systemic | no | 2L | Integer. How many distinct sites must show a control detection before it counts as systemic rather than local. Default 2. Only used when site_col is supplied. |
| min_control_obs | no | 2L | Integer. Minimum number of distinct controls a taxon must appear in before the rate comparison is allowed to condemn it. Default 2. Only used when require_control_evidence = TRUE. This exists because the direction test is a BARE RATE INEQUALITY, and rates built on one observation are not comparable to rates built on hundreds: with 91 controls against 1,052 samples, one stray read in one blank scores 1/91 = 0.011 and outvotes two genuine detections at 2/1052 = 0.0019. On real data 55-63 per cent of everything the gate condemned rested on a single control observation, and the tail contained genuine organisms. Setting this to 1 restores the unfloored behaviour; a proper one-sided significance test with a multiple-testing correction would be the principled replacement and is NOT implemented. |
| verbose | no | TRUE | Logical. Print summary messages. Default TRUE. |

**Value:** A data frame with one row per taxon, sorted by 'observation_validity' (most likely contaminants first). Columns: '{taxon_col}' Taxon identifier (from input). 'observation_validity' Numeric 0-1. Empirical Bayes-shrunk ratio of the depth-weighted field rate to the total (field + control) rate. Higher = more likely a real, genuine detection; lower = more likely a contaminant. Approaches, but ...

### flag_handler(input_df, datetime_col = "datetime", taxon_col = "taxon_name", group_col = NULL, interval_minutes = 30, handler_taxa = NULL, station_metadata = NULL, deploy_col = "deploy_time", retrieve_col = "retrieve_time", verbose = TRUE)

Flag Detections Near Start or End of a Sampling Period

Identifies detections that occur within a user-specified time interval of the earliest or latest timestamp in each group (e.g., camera station, sampling event). Detections near these edges are likely handler artifacts (researcher setting up or retrieving equipment).

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame with at minimum a datetime column, a taxon column, and optionally a grouping column (e.g., station or site). |
| datetime_col | no | "datetime" | Character. Column name containing timestamps. The function attempts to parse with several common formats. Default "datetime". |
| taxon_col | no | "taxon_name" | Character. Column name identifying taxa. Default "taxon_name". |
| group_col | no | NULL | Character or NULL. Column name for grouping (e.g., camera station). Min/max times are computed within each group. If NULL, all rows are treated as one group. Default NULL. |
| interval_minutes | no | 30 | Numeric. Minutes from the earliest or latest timestamp within each group to flag. Default 30. |
| handler_taxa | no | NULL | Character vector or NULL. If supplied, only these taxa are flagged (e.g., "Homo sapiens"). Other taxa within the interval receive a score but are flagged "valid". Besides the researcher themselves, this can include any species plausibly present specifically because of handling activity rather than the wildlife the camera is meant to detect -- e.g. a domestic dog accompanying a field crew (c("Homo sapiens", "Canis familiaris")). If NULL, all taxa within the interval are flagged. Default NULL. |
| station_metadata | no | NULL | Data frame or NULL (default). One row per group_col value with real deploy/retrieve timestamps -- see "Edge anchoring" above. Requires group_col to be non-NULL (a single implicit "all" group has no per-station metadata to key on). Must contain group_col plus deploy_col/retrieve_col. |
| deploy_col | no | "deploy_time" | Character. Column name in station_metadata for the true equipment-setup timestamp. Default "deploy_time". |
| retrieve_col | no | "retrieve_time" | Character. Column name in station_metadata for the true equipment-retrieval timestamp. Default "retrieve_time". |
| verbose | no | TRUE | Logical. Print summary messages. Default TRUE. |

**Value:** The input data frame with four columns appended: 'validity_flag' Character. '"valid"' (genuine detection), '"questionable_handling"', or '"invalid_handling"' (probable handler artifact). Fixed column name across every TaxaFlag flag_*() mechanism - see '@section Unified validity schema' above. 'observation_validity' Numeric 0-1. 1.0 for detections outside the interval; decreasing toward 0 as ...

### flag_watch_candidates(consensus_df, match_df, watch_taxa, observation_col = "observation_id", taxon_col = "taxon_name", score_col = "score_original", winner_col = "primary_taxon", score_margin = 0)

Flag observations where a watch-list species outscores the consensus winner

This function implements the likelihood-side half of the watch-list surveillance guarantee: since a watch-list species' occurrence prior stays low by design, the posterior alone cannot guarantee it surfaces, so raw match scores are compared directly instead (see *Why this exists*, below).

| Param | Required | Default | Doc |
|---|---|---|---|
| consensus_df | yes |  | Data frame, one row per observation -- TaxaAssign::posterior_consensus() output (or anything carrying observation_col and winner_col). |
| match_df | yes |  | Data frame of raw match candidates (e.g. the workflow's match_obj_restored) carrying observation_col, taxon_col, and score_col. |
| watch_taxa | yes |  | Character vector of watch-list species names (e.g. the workflow's INVASIVE_TAXA). Required, no default. |
| observation_col | no | "observation_id" | Character. Observation identifier column shared by both inputs. Default "observation_id". |
| taxon_col | no | "taxon_name" | Character. Candidate taxon-name column in match_df. Default "taxon_name". |
| score_col | no | "score_original" | Character. Raw match-score column in match_df (higher = better). Default "score_original". |
| winner_col | no | "primary_taxon" | Character. Winner column in consensus_df. Default "primary_taxon" (the top-posterior candidate -- present even when the final consensus upranked to a coarser rank). |
| score_margin | no | 0 | Numeric >= 0. Flag when the best watch score is within this many score units of the reference score (0 = must tie or exceed). Default 0. |

**Value:** 'consensus_df' with four added columns: watch_flag Logical. TRUE when a watch-list species scored within 'score_margin' of the winner's own best score. watch_taxon The best-scoring watch-list species for this observation (NA when no watch candidate exists). watch_score That species' best raw score (NA likewise). watch_reference_score The reference score the comparison used (winner's own best ...

### report_flags(flagged_data, verbose = FALSE)

Generate a Report Section for Quality Flagging

Summarizes the quality flags applied by TaxaFlag into a structured 'report_section' object (from TaxaTools). Auto-detects which flag types are present in the data. Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| flagged_data | yes |  | Data frame. Assignment data with flag columns from flag_contaminant, flag_handler, and/or review_assignments. |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing which flags were applied. results Template text summarizing flag counts. params Named list of flagging parameters. statistics Named list of flag counts.

### review_assignments(input_df, taxon_col = "consensus_taxon", taxon_rank_col = NULL, plausible_taxa_col = NULL, irreducible_only = TRUE, consensus_posterior_col = "consensus_posterior", winner_prior_col = "winner_prior", winner_rank_expanded_col = "winner_rank_expanded", plausible_posteriors_col = "plausible_posteriors", consensus_plausibility_col = "consensus_plausibility", consensus_discrimination_col = "consensus_discrimination", dist_nearest_occupied_km_col = "dist_nearest_occupied_km", patch_diameter_km_col = "patch_diameter_km", beyond_buffer_col = "beyond_buffer", inat_in_range_col = "in_range", inat_n_observations_col = "n_observations", inat_matched_name_col = "matched_name", context, target_group = NULL, marker = NULL, data_type, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), taxa_per_call = 15L, max_tokens = NULL, max_retries = 2L, pause_seconds = 1, cache_dir = NULL, on_unreviewed = c("warn", "error", "ignore"), verbose = TRUE)

LLM Expert Review of Taxonomic Assignments

Sends unique taxa from a consensus table to an LLM for structured expert review. The LLM assesses each taxon for habitat fit, geographic plausibility, contaminant risk, and (optionally) taxonomic scope. It also suggests plausible alternative taxa where appropriate.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame with at minimum a column of taxon names. |
| taxon_col | no | "consensus_taxon" | Character. Column name for consensus taxon. Default "consensus_taxon". |
| taxon_rank_col | no | NULL | Character or NULL. Column name for consensus rank (e.g., "species", "genus"). When supplied, the rank is included in the prompt for context. Default NULL. |
| plausible_taxa_col | no | NULL | Character or NULL. Name of the list column containing per-observation plausible candidate taxa (e.g., "plausible_taxa" from TaxaAssign::posterior_consensus()). When supplied, the LLM receives the full candidate set for each unique combination rather than just the upranked consensus taxon. Singletons are reviewed by species name as usual. Unresolved rows (empty candidate set) are skipped. Default NULL (current behaviour -- deduplicates on taxon_col). |
| irreducible_only | no | TRUE | Logical. When plausible_taxa_col is supplied and an irreducible_consensus column is present in input_df (added by TaxaAssign::add_slash_taxon()), only candidate sets where irreducible_consensus == TRUE are reviewed. Non-irreducible rows receive NA review columns. When irreducible_consensus is absent, all unique candidate sets are reviewed with a message. Ignored when plausible_taxa_col = NULL. Default TRUE. |
| consensus_posterior_col | no | "consensus_posterior" | Character or NULL. Column name for TaxaAssign::posterior_consensus()'s consensus_posterior -- the pipeline's own statistical confidence in the winning taxon. When present, the median value across every row sharing a taxon/candidate-set label is shown to the LLM as context (e.g. "pipeline posterior=0.81"), so a sharp disagreement between the pipeline's confidence and the LLM's ecological plausibility judgment can be surfaced in review_comment. Purely additive text -- never changes which rows are reviewed or any output column. Silently skipped when the named column is absent from input_df. Default "consensus_posterior" (matches posterior_consensus()'s own output). Set to NULL to disable. |
| winner_prior_col | no | "winner_prior" | Character or NULL. Column name for posterior_consensus()'s winner_prior -- the occurrence- database prior for the winning taxon. Same treatment as consensus_posterior_col: shown as median context (e.g. "occurrence prior=0.42"), silently skipped when absent. Default "winner_prior". Set to NULL to disable. |
| winner_rank_expanded_col | no | "winner_rank_expanded" | Character or NULL. Column name for posterior_consensus()'s winner_rank_expanded -- TRUE when the winning species-level call was manufactured by join_priors()'s coarse-rank expansion from occurrence-prior mass alone, with no direct sequence/image/acoustic evidence discriminating between candidates. When TRUE for any row sharing a label, a note to that effect is added to the LLM's context, since this changes how much weight the identification itself deserves. Silently skipped when absent. Default "winner_rank_expanded". Set to NULL to disable. |
| plausible_posteriors_col | no | "plausible_posteriors" | Character or NULL. Column name for posterior_consensus()'s plausible_posteriors list column (per-candidate posterior weights, positionally aligned with plausible_taxa_col). Only used when plausible_taxa_col is supplied. When present, each multi-candidate label's per-candidate weights are averaged across every row sharing that label and shown to the LLM (e.g. "candidate weights: Bos javanicus 72%, Bos primigenius 28%"), so review_comment can speak to the specific weaker member instead of the group as an undifferentiated set. Silently skipped when absent. Default "plausible_posteriors". Set to NULL to disable. |
| consensus_plausibility_col | no | "consensus_plausibility" | Character or NULL. Column name for add_posthoc_assessment()'s consensus_plausibility -- specifically its "unprecedented" value (no local occurrence record at all, a pipeline-computed fact, never a threshold on a prior VALUE -- see that function's own docs for why). When present, shown to the LLM as "pipeline flags UNPRECEDENTED: ..." and used to gate the skepticism GUIDELINES bullet (see @section Skepticism gate below) and the deterministic geographic_disagreement_basis output column. Silently skipped when absent. Default "consensus_plausibility". Set to NULL to disable. |
| consensus_discrimination_col | no | "consensus_discrimination" | Character or NULL. Column name for add_posthoc_assessment()'s consensus_discrimination -- specifically its "indistinguishable" value (a one-sided tail probability says a confusable relative could score just as well). Same treatment as consensus_plausibility_col. Default "consensus_discrimination". Set to NULL to disable. |
| dist_nearest_occupied_km_col | no | "dist_nearest_occupied_km" | Character or NULL. Column name for check_gbif_tile_range()'s dist_nearest_occupied_km -- distance from the study site to the nearest GBIF-mapped occurrence of the taxon, worldwide. Shown as median context (e.g. "GBIF: nearest occurrence ~41km away") alongside patch_diameter_km_col when both are present. Silently skipped when absent. Default "dist_nearest_occupied_km". Set to NULL to disable. |
| patch_diameter_km_col | no | "patch_diameter_km" | Character or NULL. Column name for check_gbif_tile_range()'s patch_diameter_km -- shown alongside dist_nearest_occupied_km_col as a rough size for the occupied area found (see "Spatial context" below for why this matters to interpretation). Silently skipped when absent, or when dist_nearest_occupied_km_col is not shown. Default "patch_diameter_km". Set to NULL to disable. |
| beyond_buffer_col | no | "beyond_buffer" | Character or NULL. Column name for check_gbif_tile_range()'s beyond_buffer -- when TRUE, shown instead of the distance/patch note as "GBIF: no occurrence found anywhere globally". Silently skipped when absent. Default "beyond_buffer". Set to NULL to disable. |
| inat_in_range_col | no | "in_range" | Character or NULL. Column name for TaxaFetch::check_inat_range()'s in_range. Shown as "in range"/"outside range" alongside inat_n_observations_col/inat_matched_name_col when present. Silently skipped when absent. Default "in_range". Set to NULL to disable. |
| inat_n_observations_col | no | "n_observations" | Character or NULL. Column name for check_inat_range()'s n_observations. Default "n_observations". Set to NULL to disable. |
| inat_matched_name_col | no | "matched_name" | Character or NULL. Column name for check_inat_range()'s matched_name -- the taxon iNaturalist's own name search actually resolved the query to, which is not always the query taxon itself. When it differs from the taxon under review, this is flagged in the prompt as "matched to '...' (name differs from query)" -- a plain factual annotation, not a judgment (see "Spatial context" below). Default "matched_name". Set to NULL to disable. |
| context | yes |  | Named list or data frame describing the study context. Recognised fields: geography (or ecoregion), habitat (or main_habitat), date. A build_context() output works directly. At minimum, supply geography and habitat. |
| target_group | no | NULL | Character or NULL. Taxonomic target group (e.g., "fish", "birds"). When supplied, the LLM populates llm_scope_plausibility. Default NULL. |
| marker | no | NULL | Character or NULL. Molecular marker or detection method (e.g., "12S", "COI", "camera trap"). Provides contaminant context. Default NULL. |
| data_type | yes |  | Character. Detection method: one of "eDNA", "acoustic" or "image". REQUIRED -- there is no default, because the value changes the contaminant-assessment guidance the LLM is given, and a wrong assumption there is silent. State the method explicitly. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Function. LLM provider function with signature function(prompt_str, ...). Default TaxaTools::call_api. Known footgun: call_api()'s provider auto-detection is set up by TaxaTools's own .onAttach(), which only runs via library(TaxaTools) -- calling this function from a fully-namespaced script (no library() calls at all) never triggers it, and call_api() silently falls back to degraded/uniform output rather than erroring. If every plausibility column comes back suspiciously uniform, pass llm_fn explicitly, e.g. function(p) TaxaTools::call_api(p, provider = "anthropic"). |
| taxa_per_call | no | 15L | Integer. Maximum taxa (or candidate sets) per LLM call. Default 15L. Candidate-set entries are longer than single taxon names; consider reducing to 8--10 when using plausible_taxa_col. |
| max_tokens | no | NULL | Integer or NULL. Maximum response tokens requested from llm_fn (forwarded as llm_fn(prompt, max_tokens = max_tokens) whenever supplied). Default NULL -- does not pass max_tokens at all, so llm_fn's own default applies (3000L for TaxaTools::call_api()). Raise this if max_retries alone isn't resolving truncation warnings for your data -- e.g. a long, multi-marker marker string can inflate per-taxon response length enough that even the smallest retry sub-batch still truncates. |
| max_retries | no | 2L | Integer. The per-batch retry budget, shared by two mechanisms. (1) When a batch's LLM response is truncated, empty, or unparseable, the batch is automatically split in half and retried -- a smaller batch requests a proportionally shorter response, directly relieving token-budget pressure. (2) When a response parses cleanly and is the right shape but simply OMITS specific taxa, those taxa (and only those) are re-asked in a follow-up call. The second case is not truncation, so the halving retry never fires for it -- see @section Unreviewed rows for how omitted taxa are recovered instead. Both stop after max_retries attempts and fall back to NA defaults for whatever is still missing. Neither applies to a hard llm_fn error (e.g. network/auth failure): a smaller or narrower batch can't fix that, so it is reported immediately without retrying. 0L disables both mechanisms, meaning exactly one call per batch. Default 2L. |
| pause_seconds | no | 1 | Numeric. Seconds to pause between LLM calls. Default 1. |
| cache_dir | no | NULL | Character or NULL (default). Directory for the per-taxon review cache. NULL disables caching entirely. Supplying a directory makes a re-run REPRODUCIBLE and stops it re-paying for verdicts already obtained: the review is a judgement, and two GreatLakes runs 50 minutes apart on identical input disagreed about Pimephales vigilax ("possible" then "unlikely"), putting it in one species list and not the other. One small .rds per reviewed taxon, keyed on everything that can move a verdict -- the taxon label and rank, its attached pipeline/weight/spatial notes, context, target_group, marker, data_type and the candidate-set path -- so changing any of them is correctly a miss. Manage it with taxaflag_clear_cache(), which uses the same TaxaTools::list_cache_files() engine as the other packages' cache helpers, so it does not accumulate unmanaged. |
| on_unreviewed | no | c("warn", "error", "ignore") | Character. What to do when taxa still have no verdict after the re-asks: "warn" (default) reports them and continues, "error" stops the run, "ignore" is silent. The residue is recorded on the result either way (see @section Unreviewed rows). Production workflows pass "error": an unreviewed row is dropped by the usual export filters, so a run with residue produces a species list that is silently short. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** The input data frame with 8 or 9 columns appended: 'llm_habitat_plausibility' likely / possible / unlikely. See '@section Column naming' below for why this and the next three columns carry an 'llm_' prefix. 'llm_geographic_plausibility' likely / possible / unlikely. 'llm_scope_plausibility' likely / possible / unlikely, or 'NA' if 'target_group' not supplied. 'llm_contamination_risk' high / ...

### review_spatial_context(input_df, query_lat, query_lon, taxon_col = "primary_taxon", plausibility_col = "primary_plausibility", occurrence_data = NULL, excluded_occurrence_data = NULL, occurrence_taxon_col = "taxon_name", occurrence_lat_col = "decimalLatitude", occurrence_lon_col = "decimalLongitude", inat_range = NULL, inat_taxon_col = "taxon_name", live_inat_check = TRUE, inat_cache_dir = NULL, inat_radius_km = 500, context = NULL, target_group = NULL, marker = NULL, data_type, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), tile = "CartoDB.Positron", gbif_style = "classic.point", gbif_bin_size = 256L, gbif_year_range = NULL)

Interactive Spatial Review of Consensus Taxa

Opens a Shiny gadget for scrolling through consensus taxa - grouped by plausibility (e.g. '"expected"'/'"unexpected"'/'"unprecedented"' from 'add_posthoc_assessment()''s 'primary_plausibility') - and seeing, for whichever taxon is selected, a live GBIF occurrence-density map plus the same numeric spatial context 'check_gbif_tile_range()' and 'compute_local_occurrence_distance()' compute, so a reviewer can look at a flagged taxon's real-world distribution without leaving the pipeline.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame of consensus taxa (e.g. consensus_final after add_posthoc_assessment()). Must contain taxon_col; supply plausibility_col = NULL if there is no grouping column to filter by. |
| query_lat | yes |  | Numeric scalars. The study site to check distances/tiles against. |
| query_lon | yes |  | Numeric scalars. The study site to check distances/tiles against. |
| taxon_col | no | "primary_taxon" | Character. Column in input_df naming each taxon. Default "primary_taxon". |
| plausibility_col | no | "primary_plausibility" | Character or NULL. Column in input_df used to group the taxon dropdown (e.g. "primary_plausibility"). NULL shows every taxon in one unfiltered list. Default "primary_plausibility". |
| occurrence_data | no | NULL | Data frame or NULL. Already-fetched occurrence records this study kept (e.g. occurrences_clean) passed straight to compute_local_occurrence_distance() and overlaid on the map as small, semi-transparent points for the selected taxon (deliberately understated so they don't visually overwhelm the GBIF tile layer underneath). NULL (default) omits the free/local panel and the point overlay entirely. |
| excluded_occurrence_data | no | NULL | Data frame or NULL. Occurrence records this study's own GBIF quality/outlier/institution/spatial-QC filtering excluded, in the same shape as occurrence_data -- overlaid as hollow red rings, distinct from occurrence_data's solid points, for provenance ("what did we have and choose not to use") rather than as evidence of presence. Not computed here -- reconstruct it yourself, e.g. dplyr::anti_join(raw_gbif, geo_outlier_check, by = "gbifID") for the filter_gbif_quality() stage specifically (see TaxaFetch::filter_gbif_quality()'s own removed_records attribute for exact per-record reasons when that attribute is still attached). NULL (default) omits this overlay. |
| occurrence_taxon_col | no | "taxon_name" | Character. Column names shared by occurrence_data AND excluded_occurrence_data. Defaults match compute_local_occurrence_distance()'s own defaults. |
| occurrence_lat_col | no | "decimalLatitude" | Character. Column names shared by occurrence_data AND excluded_occurrence_data. Defaults match compute_local_occurrence_distance()'s own defaults. |
| occurrence_lon_col | no | "decimalLongitude" | Character. Column names shared by occurrence_data AND excluded_occurrence_data. Defaults match compute_local_occurrence_distance()'s own defaults. |
| inat_range | no | NULL | Data frame or NULL. Pre-computed TaxaFetch::check_inat_range() output (one row per taxon, with in_range/n_observations/matched_name) to look up by taxon name -- checked FIRST, for free, before any live call (see live_inat_check below). Real, confirmed limitation this param alone can't cover: check_inat_range() is typically only ever run on a pipeline's own undetected/unreferenced candidate list (e.g. Step 8c of a workflow script), not every taxon in a consensus table -- verified directly against a real dataset that taxa flagged "expected" or "unexpected" (not "unprecedented") are routinely absent from it entirely, which is why live_inat_check exists. |
| inat_taxon_col | no | "taxon_name" | Character. Taxon-name column in inat_range. Default "taxon_name". |
| live_inat_check | no | TRUE | Logical. When a taxon has no row in inat_range (including when inat_range itself is NULL), fall back to a real, live TaxaFetch::check_inat_range() call for just that one taxon. Default TRUE -- unlike review_assignments()'s "Run AI Review" button, this is free (no LLM billing) and fires automatically on selection, matching check_gbif_tile_range()'s own always-on treatment. Requires the TaxaFetch package and a real INAT_API_TOKEN; silently falls back to "no data" (not an error) when either is unavailable, or when iNat itself has no polygon for the resolved taxon (surfaced via range_status in that case, e.g. "taxon_not_found"/"no_polygon", rather than a blanket "no data" that can't be told apart from "never checked"). |
| inat_cache_dir | no | NULL | Character or NULL. Forwarded to check_inat_range()'s own cache_dir when live_inat_check fires -- caches per-taxon iNat range polygons on disk so re-selecting the same taxon (in this session or a later one) doesn't re-download it. NULL (default) disables caching, matching check_inat_range()'s own default. |
| inat_radius_km | no | 500 | Numeric. Search radius (kilometers) for the real iNaturalist observation points plotted on the map (see .fetch_inat_points(), internal) -- distinct from live_inat_check's range-polygon check, which has no radius concept. Default 500 -- confirmed live this needs to be wide, not just permissive: the individual-point map layer only shows points within this radius, unlike a full-coverage density tile (continuous world density, like GBIF's own tiles), so too small a radius can make even a well-recorded taxon look confined to "a small region." A smaller default (50km, copied unexamined from an unrelated function's own default) was confirmed live to do exactly this. A dashed circle of this exact radius is drawn on the map (grouped with the iNat points layer, so toggling one toggles both) specifically so a taxon with no visible points nearby doesn't read as "no iNat data exists" when it may just mean "none within this radius." |
| context | no | NULL | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| target_group | no | NULL | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| marker | no | NULL | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| data_type | yes |  | Character. Detection method, passed straight to review_assignments(): one of "eDNA", "acoustic" or "image". REQUIRED, and required even when the "Run AI Review" button is never clicked, because the value changes the guidance the LLM receives and defaulting it would make that choice silently. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| tile | no | "CartoDB.Positron" | Character. Leaflet base-map tile provider (the reference map underneath the GBIF density overlay). Default "CartoDB.Positron" -- a muted, mostly-grayscale basemap chosen specifically so GBIF's own density colours stand out (a busier basemap like "OpenStreetMap"'s default styling visually competes with them, especially at low zoom where GBIF's own density pixels are small). Try "CartoDB.PositronNoLabels" for an even plainer background (drops place-name labels too). |
| gbif_style | no | "classic.point" | Character. GBIF map API style query parameter, controlling how GBIF itself renders density (colour ramp, point vs. area aggregation). Default "classic.point" -- GBIF's own default rendering, matching what GBIF's own map viewer shows. A bare ".point" style is automatically upgraded to its ".poly" counterpart and combined with gbif_bin_size (below) unless it's a Heat-family style, which has no .poly counterpart. Other .point styles (e.g. "purpleHeat.point") are valid and can look bolder against a light basemap; pass one to compare. |
| gbif_bin_size | no | 256L | Integer or NULL. GBIF map API's bin= square/squareSize binning parameters, aggregating raw single-pixel occurrence dots into visibly larger squares -- confirmed live before choosing this default: squareSize params are silently NO-OPS when style stays .point-suffixed (identical bytes with/without them), and only take effect once the style is switched to its .poly counterpart, which is why gbif_style is auto-upgraded above. Default 256L, chosen from real measurements against the SPARSE species this gadget is actually meant to review (this thread's own real "unprecedented" candidates, at the real zoom-7 study-site tile), not a common/ everywhere-present species -- a smaller default (64) would look like no noticeable change, which real measurement confirms: for a real, genuinely sparse GBIF record set at that exact tile, raw .point pixels covered under 0.1%; squareSize=64 only reaches ~1-2.5%, visually indistinguishable from unbinned dots on a full map pane. 256 reaches ~10-15% coverage for the same real sparse species (a ~60-140x increase over raw pixels) while a maximally common, everywhere-present species (checked separately, not this gadget's typical use case) only reaches ~26% -- visibly bigger without turning into a solid blob. NULL disables binning entirely, reverting to gbif_style exactly as supplied. ".poly"-suffixed styles combined with gbif_bin_size = NULL (unbinned) can render as a completely EMPTY tile at a real zoom/species combination that raw .point styles render correctly -- confirmed live, not a safe combination -- so this is only ever applied together with binning, never on its own. A binned square can visually sit offset from a point's true location by up to gbif_bin_size pixels, since GBIF snaps each occurrence to its containing bin before drawing it -- a real, expected consequence of aggregation, not a data or rendering bug (a single domestic-cat record appearing a few km into open water at the default 256L binning is exactly this: GBIF's real, unfiltered occurrence data plus one coarse pixel's worth of legitimate positional imprecision from binning, not a broken map layer). See also check_gbif_tile_range()'s own What the PNG can and can't tell you section -- density tiles are a display aid, not an exact-count source, in this gadget as much as there. |
| gbif_year_range | no | NULL | Character or NULL. GBIF map API year query parameter (e.g. "1995,2025"), display-only -- affects only the visual tile layer, NOT check_gbif_tile_range()'s own distance/patch numbers (which deliberately stay all-time/global, the right question for "is this plausible anywhere, ever" rather than "within our exact study window"). Worth knowing: the density map is all-time and worldwide by default, which is often a much LARGER pool of records than a study's own date- and quality-filtered GBIF fetch -- confirmed directly against the real GBIF tile API that a narrower year range genuinely reduces what's rendered (a real, working filter, not a cosmetic one). NULL (default) shows GBIF's full all-time record, matching GBIF's own default map view. |

**Value:** 'NULL' invisibly. The gadget is for interactive exploration only.

### taxaflag_clear_cache(cache_dir = tools::R_user_dir("TaxaFlag", "cache"), older_than_days = NULL, dry_run = FALSE)

Report and clear TaxaFlag's on-disk caches

Lists, and optionally deletes, the per-key files written by 'review_assignments()' and 'check_gbif_tile_range()' when either is given a 'cache_dir': 'review_assignments()''s per-reviewed-taxon LLM verdict cache, and 'check_gbif_tile_range()''s per-(taxon, location, zoom, ...) GBIF density-tile verdict cache. Entries in both have no built-in expiry - a verdict stays valid until its own key changes (e.g. the taxon's review context changes, or the query location/zoom changes), which makes it a miss anyway - so pruning is about disk usage and about deliberately forcing a fresh ...

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaFlag", "cache") | Character. The directory passed to review_assignments()'s or check_gbif_tile_range()'s cache_dir (each function's cache lives in its own directory, so point this at whichever one you want to inspect/clear). Defaults to tools::R_user_dir("TaxaFlag", "cache"), matching the sibling packages; workflows that pass a project-local directory should pass the same one here. |
| older_than_days | no | NULL | Optional numeric. Delete only entries older than this many days. NULL (default) considers every entry. |
| dry_run | no | FALSE | Logical. TRUE reports what would be deleted without deleting it. |

**Value:** Invisibly, the inventory data frame ('TaxaTools::list_cache_files()' output) of the files considered.

### validate_controls(input_df, event_col = "event_id", taxon_col = "taxon_name", count_col = "count", control_samples, site_col = NULL, min_samples_per_site = 3L, headroom_fraction = 0.5, headroom_limit = 0.98, max_null_pairs = 500L, verbose = TRUE)

Validate That Control Samples Actually Look Like Controls

Tests whether each column labelled a control is compositionally consistent with being one, and - in the other direction - whether any column labelled a field sample looks like a control. Mislabelling runs both ways, and a mislabelled field sample sitting in the control set is the more damaging of the two: it makes the real community look like contamination, so 'flag_contaminant' then filters genuine signal.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Long-format data frame: one row per taxon x column observation, carrying at least event_col, taxon_col and count_col. |
| event_col | no | "event_id" | Character. Column identifying the sampled/observed unit (filter, bottle, replicate, recording, or image batch). Default "event_id". |
| taxon_col | no | "taxon_name" | Character. Column identifying the feature to compare compositions on -- a fine-grained candidate/detection ID (e.g. ESV/ASV for sequence data, a call/image ID for acoustic/image data) is preferable to a taxon name, because it does not depend on assignment succeeding. Default "taxon_name". |
| count_col | no | "count" | Character. Count column. Default "count". |
| control_samples | yes |  | Character vector of event_col values that are labelled controls. |
| site_col | no | NULL | Character or NULL. Column grouping columns into sites. When NULL every column is treated as one site, which makes the null a whole-study one and weakens the test; a warning says so. |
| min_samples_per_site | no | 3L | Integer. Below this many field samples a site cannot form its own null. Default 3. |
| headroom_fraction | no | 0.5 | Numeric in (0, 1). A control is consistent with being a control when its median distance to the site's samples is at least this far along the room remaining above the sample median: threshold = median(null) + headroom_fraction * (1 - median(null)). Default 0.5, i.e. halfway between "as distant as the samples are from each other" and "completely disjoint". THIS FORM WAS ARRIVED AT BY FAILING TWICE ON REAL DATA, and both failures are worth knowing because each looked reasonable: A high QUANTILE of the null (0.90) is in-range but not robust. A control mislabelled as a sample sits inside the sample set and inflates the very null it is tested against -- with 8 samples plus one disjoint hidden control, 22% of sample-pair distances go to ~1.0 and drag the quantile into the contaminated tail. It also has no headroom at heterogeneous sites: a real site with 1,151 samples had a 0.90-quantile of exactly 1.000, so nothing could pass. An additive robust fence, median + 3 * MAD, is robust but LEAVES THE METRIC'S RANGE. Bray-Curtis is bounded at 1, and on real sites this produced thresholds of 1.54 and 1.62, after which the headroom guard fired on 59 of 84 controls. Robustness is not worth an impossible cutoff. Scaling into the remaining headroom is bounded by construction (it can never exceed 1) and depends only on the median, so it keeps the 50% breakdown point that made MAD attractive. |
| headroom_limit | no | 0.98 | Numeric. If a site's null threshold reaches this value the test has no headroom above the samples and cannot pass anything: a control would have to be MORE disjoint than the samples already are from each other. Such columns are reported "untestable_no_headroom" rather than given a confident verdict. Found on real data: a site with 1,151 samples had a null 0.90-quantile of exactly 1.000, which flagged genuine 6-taxon controls as resembling 34-taxon samples. Default 0.98. |
| max_null_pairs | no | 500L | Integer. Cap on the number of sample-pair distances used to estimate a site's null. The null is O(n^2) in samples, and a real site here had 213 samples = 22,578 pairs, which made the first version of this function unusable (still running after 19 minutes). A few hundred pairs estimate a median and a 0.90 quantile perfectly well, so pairs are sampled at random above this cap and null_n_pairs records how many were actually used. Default 500. |
| verbose | no | TRUE | Logical. Print a summary. Default TRUE. |

**Value:** A data frame, one row per sequenced column, with the column id, its site, its label, 'n_taxa', 'n_reads', the test statistic 'd_to_samples', the site null ('null_median', 'null_threshold', 'null_n_pairs'), a 'power' verdict and a 'verdict'. Attribute '"site_power"' carries the per-site table. 'verdict' takes: '"consistent_with_control"', '"RESEMBLES_SAMPLE"' (a control that may be a ...

## Quick Start

### Check that the blanks really are blanks (do this first)

``` r
library(TaxaFlag)

checked <- validate_controls(
  input_df        = reads_long,
  event_col       = "event_id",
  taxon_col       = "ESVId",     # a fine-grained candidate/detection ID beats
  count_col       = "n_reads",   # a taxon name: it does not depend on
  control_samples = blank_ids,   # assignment having succeeded
  site_col        = "Site"       # supply this if you have it; the null is per site
)

# controls that look like field samples, and samples that look like controls
checked[checked$verdict %in% c("RESEMBLES_SAMPLE", "RESEMBLES_CONTROL"), ]

# and read the power before believing a clean result
attr(checked, "site_power")
```

### Flag contamination from lab blanks

``` r
flagged <- flag_contaminant(
  input_df               = reads_long,
  taxon_col        = "taxon_name",
  count_col        = "n_reads",
  event_col        = "event_id",
  control_samples  = c("Blank_1", "Blank_2"),
  contaminant_type = "lab_contaminant"
)

# Output adds: observation_validity, validity_flag, validity_reason
# Filter to invalid taxa (probable contaminants)
flagged[flagged$validity_flag == "invalid_lab_contaminant", ]
```

For new work, gate on evidence and use site breadth:

``` r
gated <- flag_contaminant(
  input_df                 = reads_long,
  taxon_col                = "ESVId",
  count_col                = "n_reads",
  event_col                = "event_id",
  control_samples          = blank_ids,
  require_control_evidence = TRUE,   # no verdict without a control detection
  site_col                 = "Site", # systemic vs local
  min_control_obs          = 2L     # don't condemn on ONE blank observation
)

# what to actually remove
gated[gated$validity_flag == "invalid_lab_contaminant", ]
# what NOT to remove, though the ungated path would have
gated[gated$validity_flag == "not_control_enriched", ]
# and what simply cannot be assessed
table(gated$validity_flag)
```

### Flag handler artifacts (camera traps)

``` r
flagged <- flag_handler(
  input_df               = camera_detections,
  datetime_col     = "datetime",
  group_col        = "camera_id",
  interval_minutes = 30
)
```

### LLM expert review

``` r
reviewed <- review_assignments(
  input_df         = consensus_results,
  taxon_col  = "consensus_taxon",
  context    = list(geography = "Southern California", habitat = "Marine"),
  target_group = "fish"
)
# Returns 8 structured columns (llm_-prefixed: independent LLM judgments,
# never derived from the pipeline's own values):
# llm_habitat_plausibility, llm_geographic_plausibility, llm_scope_plausibility,
# llm_contamination_risk, review_alternatives, review_lower_hypotheses,
# review_confidence, review_comment

# Filter to contamination concerns
reviewed[reviewed$llm_contamination_risk %in% c("high", "moderate"), ]
```

