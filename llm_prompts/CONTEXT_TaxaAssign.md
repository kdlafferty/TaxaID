# CONTEXT: TaxaAssign

**Bayesian Taxonomic Assignment from Match Scores and Priors**

Estimates the posterior probability that a biological sample (sequence, image, sound) was produced by a particular taxon, using Bayes' theorem. Combines per-taxon likelihoods (from TaxaLikely or an LLM) with spatial priors (from TaxaExpect or an LLM) to compute posteriors via Monte Carlo simulation. Provides consensus taxonomy assignment at the appropriate rank (species, genus, family, etc.), empirical Bayes prior refinement, score-based consensus for comparison, and automated report generation. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-20 21:06:30 UTC; unix). 16 exported function(s).

## Functions

### add_slash_taxon(consensus_df, taxa_col = "plausible_taxa", posteriors_col = "plausible_posteriors")

Add Slash Taxon Name and Irreducibility Flag to a Consensus Dataframe

Appends two columns to the output of 'posterior_consensus()':

| Param | Required | Default | Doc |
|---|---|---|---|
| consensus_df | yes |  | Dataframe. Output of posterior_consensus(). Must contain a list column of character vectors giving the plausible candidate taxa per observation (see taxa_col). |
| taxa_col | no | "plausible_taxa" | Character. Name of the list column containing per-observation plausible taxa vectors. Default "plausible_taxa". |
| posteriors_col | no | "plausible_posteriors" | Character. Name of the list column containing per-observation posterior probability vectors, positionally aligned with taxa_col (e.g., "plausible_posteriors" from posterior_consensus()). When present, candidates within each slash name are ordered by descending posterior (most probable first). When NULL or absent from consensus_df, candidates are ordered alphabetically. Default "plausible_posteriors". |

**Value:** 'consensus_df' with additional columns appended: 'slash_taxon_name' (character) and 'irreducible_consensus' (logical). When 'consensus_df' has a 'consensus_taxon' column, two more columns are added: 'consensus_OTU' Single reporting label per observation — 'slash_taxon_name' when non-'NA', otherwise 'consensus_taxon'. Use this as the one column with a non-'NA' label for every resolved observation. 

### adjust_inat_range_priors(likelihoods_ready, inat_range, n_obs_threshold = 500L, require_name_match = TRUE, verbose = FALSE)

Elevate priors for iNaturalist range-supported unobserved taxa

For unobserved eDNA candidates (taxa detected by BLAST but absent from the regional occurrence database), promotes any taxon that (a) falls within its iNaturalist geomodel range polygon at the study site and (b) has sufficient iNaturalist observation coverage to treat the polygon as reliable, from its current group prior up to the Tier 2 singleton-mirror floor.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihoods_ready | yes |  | Data frame. Output of join_priors(). Must contain taxon_name, alpha, prior_alpha, prior_beta, prior_mean, singleton_alpha, singleton_beta. |
| inat_range | yes |  | Data frame. Output of TaxaFetch::check_inat_range(). Must contain taxon_name, in_range, n_observations. |
| n_obs_threshold | no | 500L | Integer. Minimum iNaturalist observation count required for the range polygon to be considered reliable. Default 500. Set higher for less-observed taxonomic groups. Taxa below this threshold are not elevated even if in_range = TRUE. |
| require_name_match | no | TRUE | Logical, default TRUE. Exclude rows whose resolved iNat name (name_match column, check_inat_range() 2026-08-28+) differs from the query or cannot be verified -- iNat's fuzzy text search can silently resolve a query to a different species, and an elevation must never ride on a misresolved name. |
| verbose | no | FALSE | Logical. If TRUE, reports the number of taxa and rows elevated. Default FALSE (a summary is always emitted via cli::cli_inform). |

**Value:** 'likelihoods_ready' with 'prior_alpha', 'prior_beta', and 'prior_mean' elevated to the Tier 2 singleton-mirror floor for qualifying taxa. Adds a logical column 'inat_range_elevated' (TRUE for elevated rows, FALSE otherwise).

### assign_taxa_llm(match_df, context = NULL, context_group = NULL, llm_fn = NULL, score_threshold = 80, top_n = 10L, rank_system = NULL, score_sharpness = 0.1, unknown_lik_weight = 0.05, unreferenced_taxa = NULL, known_present = NULL, known_absent = NULL, absent_detection_prob = 0.8, taxa_per_call = 15L, pause_seconds = 1, prior_phi = c(high = 50, moderate = 10, low = 3), prior_weight_guide = list(native_expected = c(0.5, 1), native_occasional = c(0.03,      0.15), native_unlikely = c(0.003, 0.03), nearby_expected = c(0.05,      0.3), nearby_occasional_unlikely = c(0.002, 0.05), not_documented = c(0.001,      0.02), taxonomically_impossible = c(1e-04, 0.002)), n_sims = 1000L, verbose = FALSE)

Assign Taxa Using an LLM-Approximated Bayesian Pipeline

Assign Taxa Using an LLM-Approximated Bayesian Pipeline

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Canonical match object from TaxaMatch (or equivalent). Required columns: observation_id, score_original, taxon_name, taxon_name_rank. Optional but recommended: testid (marker type). |
| context | no | NULL | Optional data frame with location/habitat context. Either a single row (broadcast to all observations) or one row per observation_id. Recognised columns: observation_id, ecoregion, lat, lon, date, main_habitat. In the full pipeline, populate main_habitat from the main_habitat column produced by TaxaHabitat and passed through TaxaExpect. |
| context_group | no | NULL | Optional character vector of column names in context to group observations by (e.g., "ecoregion" or c("ecoregion", "habitat")). Each unique combination of values becomes a separate LLM call with its own taxon list. Requires context to have an observation_id column. NULL (default) puts all observations in one group. |
| llm_fn | no | NULL | Function or NULL. Provider function following the TaxaTools llm_fn pattern: accepts a single character string prompt and returns a single character string response. Default NULL resolves to getOption("TaxaID.llm_fn") when set, otherwise TaxaTools::call_api (requires TaxaTools installed). |
| score_threshold | no | 80 | Numeric. Minimum score to include a candidate (0-100). Default 80. |
| top_n | no | 10L | Integer. Maximum candidates per observation included in the unique taxon list sent to the LLM. Default 10. |
| rank_system | no | NULL | Optional character vector of taxonomy column names in match_df, coarse-to-fine (e.g. c("family", "genus", "species")). When NULL (default), standard taxonomy columns present in match_df are detected automatically from kingdom, phylum, class, order, family, genus, species. Detected columns are carried through to the posterior dataframe, enabling posterior_consensus() to resolve LCA above genus level. |
| score_sharpness | no | 0.1 | Numeric >= 0. Controls how strongly match score differences translate to likelihood differences via exp(score_sharpness * score). At 0.1, a 10-point score difference produces a ~2.7x likelihood difference. Higher values (e.g., 0.5) make top-scoring candidates dominate sharply; lower values (e.g., 0.01) make likelihoods nearly uniform regardless of score. Default 0.1. Set to 0 for uniform likelihood across all candidates (prior-driven). In the LLM workflow, likelihoods are intentionally a weak function of scores (sharpness = 0.1) because the LLM prior provides the main discriminating information. In the Bayesian workflow, TaxaLikely provides properly calibrated likelihoods and this parameter is not used. |
| unknown_lik_weight | no | 0.05 | Numeric in (0, 1). Baseline likelihood for the catch-all "unknown species" hypothesis (species not in any candidate list). At 0.05, the unknown hypothesis competes at 5% likelihood against named candidates. Higher values make "unknown" more competitive (conservative); lower values favor named candidates. Also used as the unknown hypothesis prior weight. Default 0.05. |
| unreferenced_taxa | no | NULL | Optional character vector of species names absent from the reference database (e.g., TaxaLikely::audit_barcode_coverage()$unreferenced). Only congeners of scored candidates are inserted per observation. NULL (default) disables unreferenced species insertion. |
| known_present | no | NULL | Optional character vector of species confirmed present at the site by independent survey (visual, net, prior eDNA, etc.). Passed to the LLM as ecological context to sharpen habitat assessment and co-occurrence reasoning. Not used in the mathematical update step. |
| known_absent | no | NULL | Optional species list of taxa surveyed for but not detected at the site, supplied as either: A character vector — all species assigned absent_detection_prob. A data frame with columns taxon_name (character) and optionally detection_prob (numeric 0–1). Missing detection_prob values fall back to absent_detection_prob. The LLM sees the list as context. In addition, each absent species' prior is multiplied by (1 - detection_prob) after the LLM call, then the full prior vector is renormalized. This is a principled Bayesian update: P(present \| not detected) ∝ P(not detected \| present) × P(present) = (1 - p_det) × prior_LLM. Only applies to species that appear as hypotheses (scored candidates or inserted unreferenced taxa); species not in the candidate set already have near-zero prior by construction. |
| absent_detection_prob | no | 0.8 | Numeric in (0, 1). Probability of detecting a species known to be absent from the study area. Applied as prior * (1 - absent_detection_prob) suppression. At 0.80, a known-absent species has its prior reduced by 80%. Represents the field survey's power to have detected the species if it were present. Used as the default when known_absent is a character vector or when a row in a known_absent data frame is missing detection_prob. Default 0.80. |
| taxa_per_call | no | 15L | Integer >= 1. Maximum number of unique taxa sent to the LLM in a single call. When the unique taxon list for a group exceeds this limit it is split into sequential batches; results are combined before joining to observations. Default 15. Lowered from a prior default of 30 (2026-07-09) after a real batch of 30 taxa truncated 4 times out of 5 at call_api()'s default max_tokens of 3000 (a 23-taxon batch succeeded in the same run) -- see .parse_taxa_response()'s truncation-specific warning. 15 also matches TaxaFlag::review_assignments()'s own default, independently lowered from 30 to 15 for the identical failure mode in an earlier session -- two independent real-data findings agreeing on the same number. Still based on real trials rather than an exhaustive sweep across response verbosity; if you still see truncation warnings, reduce further or pass an llm_fn wrapper with a higher max_tokens (e.g. function(prompt) TaxaTools::call_api(prompt, max_tokens = 8000L)). Increase if taxa are few and you prefer fewer API calls. |
| pause_seconds | no | 1 | Numeric. Seconds to pause between LLM calls (both between groups and between taxon batches within a group). Default 1. |
| prior_phi | no | c(high = 50, moderate = 10, low = 3) | Named numeric vector mapping information_quality levels to Beta distribution concentration parameter (phi = alpha + beta). Phi controls how tightly the prior is centered on the LLM's point estimate: phi = 50 ("high") is equivalent to 50 observations of data, giving a tight prior; phi = 10 ("moderate") allows substantial uncertainty; phi = 3 ("low") produces a diffuse prior that the likelihood can easily override. information_quality is the LLM's self-assessment of how much published data exists about each taxon at the study location -- it reflects data availability, not confidence in the taxonomic assignment itself. Default c(high = 50, moderate = 10, low = 3). A single unnamed scalar applies uniformly to all taxa (overrides LLM-returned quality levels). Set to NULL to disable Beta prior uncertainty entirely (priors treated as fixed, no Monte Carlo on prior side). Adjust based on how much you trust the LLM's ecological knowledge for your study system: decrease phi values for poorly documented regions or understudied taxa. |
| prior_weight_guide | no | list(native_expected = c(0.5, 1), native_occasional = c(0.03,      0.15), native_unlikely = c(0.003, 0.03), nearby_expected = c(0.05,      0.3), nearby_occasional_unlikely = c(0.002, 0.05), not_documented = c(0.001,      0.02), taxonomically_impossible = c(1e-04, 0.002)) | Named list of prior weight ranges guiding LLM assignments. Each element is a length-2 numeric vector c(min, max). The LLM uses these ranges when assigning prior probabilities based on range status and habitat fit. Names indicate the ecological scenario: native_expected, native_occasional, native_unlikely, nearby_expected, nearby_occasional_unlikely, not_documented, taxonomically_impossible. Default ranges are derived from expert ecological judgment (see package documentation). Modifying these ranges directly affects how strongly geographic and habitat information influence posterior probabilities. |
| n_sims | no | 1000L | Integer. Monte Carlo simulations for compute_posterior(). Default 1000. Set to 0 to skip simulation and return point estimates only. |
| verbose | no | FALSE | Logical. If TRUE, prints the prompt and raw LLM response for each group call. Default FALSE. |

**Value:** A data frame (the output of 'compute_posterior()') with columns: 'observation_id', 'taxon_name', 'taxon_name_rank', 'hypothesis_type', 'range_status', 'habitat_fit', 'information_quality', 'score_likelihood', 'score_likelihood_mean', 'score_likelihood_sd', 'prior_mean', 'prior_alpha', 'prior_beta', 'posterior_point_est', 'posterior_mean', 'posterior_sd', 'confidence_score'. 'prior_alpha'/'prior_be

### build_context(taxon_names, geographic_hint = NULL, date = NULL, habitat_scheme = NULL, llm_fn = NULL, chunk_size = 60L)

Build Site Context from Taxon Names

Infers a site-level context data frame ('main_habitat', 'ecoregion', 'date') from a list of candidate taxon names using LLM-based habitat assignment. This automates the manual creation of the 'context' argument required by 'assign_taxa_llm'.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of scientific names (e.g. unique(match_df$taxon_name)). |
| geographic_hint | no | NULL | Optional character string describing the approximate geographic region (e.g. "Southern California", "Chesapeake Bay watershed"). Passed to build_habitat_prompt(geographic_context = ...). When non-NULL, the LLM also returns an ecoregion_best_guess column. |
| date | no | NULL | Optional character string for the sampling date or year (e.g. "2025"). Passed through to the returned ctx data frame. |
| habitat_scheme | no | NULL | Passed to build_habitat_prompt. Default NULL (Marine / Freshwater / Terrestrial). |
| llm_fn | no | NULL | Function or NULL. LLM provider following the TaxaTools llm_fn pattern. Default NULL resolves to getOption("TaxaID.llm_fn") when set, otherwise TaxaTools::call_api (requires TaxaTools). |
| chunk_size | no | 60L | Integer. Maximum taxa per prompt chunk. Default 60. |

**Value:** A one-row data frame with columns: ecoregion Character. Inferred ecoregion, or 'NA' if 'geographic_hint' was 'NULL'. main_habitat Character. Consensus habitat across the assemblage. date Character. Passed through from the 'date' argument. The per-species habitat weight table is attached as 'attr(result, "habitats_df")' for inspection.

### combine_multisite_priors(joined)

Combine Per-Site Priors for Multi-Site Observations

Bridges 'join_priors()' (Session 138: now site-preserving, i.e. one row per 'observation_id' x 'taxon_name' x 'taxon_name_rank' x 'grid_id' x 'main_habitat') to 'compute_posterior()', which expects exactly one row per candidate hypothesis per observation. When the same 'observation_id' was detected at more than one site (e.g. the same eDNA ASV recovered from reads at two different sample sites), each candidate taxon otherwise arrives with one prior row per site. This function combines those rows into one.

| Param | Required | Default | Doc |
|---|---|---|---|
| joined | yes |  | Data frame, typically join_priors() output. Must contain observation_id, taxon_name, taxon_name_rank, grid_id, main_habitat, prior_alpha, prior_beta, prior_mean (all present in join_priors()'s output). Observations detected at only one site (the common case) pass through unchanged. |

**Value:** 'joined' with one row per 'observation_id' x 'taxon_name' x 'taxon_name_rank', plus two new columns: 'n_sites_combined' Integer. Number of per-site rows combined into this row ('1' when the candidate was detected at only one site). 'combined_sites' Character. Pipe-delimited sorted list of the combined 'grid_id' values, 'NA' for single-site rows. 'grid_id' and 'main_habitat' themselves are set to '

### compute_group_priors(taxaexpect_priors, taxonomy_map, taxon_col = "taxon_name", theta_col = "theta_mean", rank_cols = c("species", "genus", "family", "order", "class"), exclude_named_evidence = TRUE)

Aggregate occurrence-model shares to genus/family level

Builds the lookup 'posterior_consensus(group_priors = ...)' uses to compute a genuinely group-level 'consensus_prior' - the SUM of 'theta_mean' across every locally modelled member of a genus or family, not just the few candidates one observation's evidence happened to surface.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxaexpect_priors | yes |  | Data frame. The full local occurrence-prior table (e.g. TaxaExpect::generate_full_priors()'s output, or the taxaexpect_priors object already used elsewhere in this ecosystem's workflows). Must contain taxon_col and theta_col. |
| taxonomy_map | yes |  | Data frame supplying genus/family for each taxon in taxaexpect_priors (e.g. occurrences_clean, which typically has real genus/family columns even when taxaexpect_priors itself does not). Must contain taxon_col and every column named in rank_cols. |
| taxon_col | no | "taxon_name" | Character. Shared join key between the two inputs (default "taxon_name"). |
| theta_col | no | "theta_mean" | Character. Column in taxaexpect_priors holding the occurrence-model share (default "theta_mean"). |
| rank_cols | no | c("species", "genus", "family", "order", "class") | Character vector. Which columns in taxonomy_map to aggregate by (default c("species", "genus", "family")). See "Why "species" is in the default rank_cols" below -- "species" is auto-derived as taxon_col's own identity when taxonomy_map has no explicit "species" column. |
| exclude_named_evidence | no | TRUE | Logical, default TRUE. Drop rows that make a presence claim about a NAMED species with no local occurrence record -- i.e. rows carrying a real evidence_sources value (distance_clamp, regional_proximity, invasive_watch, inat_range). Since curve pricing every zero-record BLAST candidate has a clamp row, so "has a row in the priors table" stopped meaning "known locally" on 2026-08-31. Measured on the PtCon 12S run of 2026-09-13: without this filter, 256 of 264 winner-scope unprecedented rows read expected or unexpected at consensus scope, 75 of them on nothing but a clamp or evidence row (a neon tetra, a plains minnow, a red deer at a marine site), so TaxaFlag::review_assignments()'s skepticism gate never saw them. Deliberately keyed on evidence_sources, NOT on prior_branch. The resident_undetected branch holds two different things: those named evidence rows (258 of 295 at PtCon 12S), and the ANONYMOUS dark-diversity mirrors (undetected_type singleton_mirror/ global_floor, taxon_name NA, keyed by genus -- 37 rows there). A mirror exists precisely BECAUSE the group has local records, via Good-Turing on its own singletons, so it is legitimate group support and is kept. Filtering by branch would discard it: at PtCon 18S the resident rows carry no genus/family at all, so the mirrors are the dominant source of genus- and family-level group mass. FALSE restores the pre-2026-09-13 behaviour. Ignored, with that same behaviour, when taxaexpect_priors has no evidence_sources column (GLMM-era tables, and sites that predate curve pricing). |

**Value:** A data frame with one row per (rank, taxon) group actually present in the data: 'rank' (the 'rank_cols' value, e.g. '"genus"'), 'taxon' (the group's name at that rank), 'theta_sum' (sum of 'theta_col' across every member with a non-NA value, capped at 1 as a defensive guard against model-fit overshoot - see 'posterior_consensus()''s 'consensus_prior' docs), 'n_members' (count of members contributi

### compute_posterior(likelihood_w_prior, n_sims = 1000)

Compute Bayesian Posterior Probabilities

Performs the Bayesian update: Posterior ~ Likelihood * Prior. Adds posterior columns to the input dataframe and returns the full dataframe, so all existing columns (e.g., taxon name, hypothesis type, rank) are preserved.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_w_prior | yes |  | Dataframe. One row per hypothesis per observation. Must contain columns: observation_id, score_likelihood, score_likelihood_mean, score_likelihood_sd, prior_mean. Optional columns: prior_alpha and prior_beta (Beta distribution parameters). When present, Monte Carlo simulation samples priors from Beta(alpha, beta). When absent, priors are treated as fixed (no prior uncertainty). Not required unconditionally because a caller can have a genuinely fixed, non-probabilistic prior with no natural concentration parameter -- e.g. assign_taxa_llm()'s prior_phi = NULL disables Beta sampling entirely when the LLM's per-taxon confidence isn't being modelled as data volume. All other real callers in this ecosystem (join_priors()-derived TaxaExpect priors) always supply both columns. |
| n_sims | no | 1000 | Integer. Number of Monte Carlo simulations. Default 1000. Set to 0 to skip simulation and return point estimates only. |

**Value:** The input dataframe with four new columns added: • 'posterior_point_est': deterministic posterior from point estimates • 'posterior_mean': mean posterior across Monte Carlo simulations • 'posterior_sd': SD of posterior across Monte Carlo simulations • 'confidence_score': fraction of simulations in which this hypothesis won

### generate_report(result, consensus, unreferenced_result = NULL, workflow = NULL, data_type = NULL, marker = NULL, context_source = "user", study_description = NULL, llm_fn = NULL, verbose = FALSE)

Generate Publication-Ready Report from TaxaAssign Output

Produces a Methods and Results text suitable for inclusion in a scientific paper. The Methods section is assembled from templates that adapt to the workflow used (LLM-shortcut or Bayesian). The Results section summarises assignment outcomes, either as LLM-composed prose or as a structured bullet-point summary when 'llm_fn = NULL'.

| Param | Required | Default | Doc |
|---|---|---|---|
| result | yes |  | Data frame or NULL. Posterior output from compute_posterior or assign_taxa_llm. Required when consensus comes from posterior_consensus. Pass NULL when consensus comes from score_consensus (no posterior data exists). |
| consensus | yes |  | Data frame. Output from posterior_consensus or score_consensus. The consensus type is detected automatically from column presence (top_score for score-based; consensus_posterior for posterior-based) and the report adapts accordingly. |
| unreferenced_result | no | NULL | Optional. An unreferenced_species_result S3 object from suggest_unreferenced_species. When provided, the report includes reference database completeness statistics and unreferenced species findings. |
| workflow | no | NULL | Character or NULL. One of "bayesian" or "llm", describing how result/consensus were produced -- selects which Methods-text template to use. Default NULL auto-detects from column presence (range_status, habitat_fit, information_quality all present -> "llm"; otherwise "bayesian"), which is reliable for output produced by this package's own run_bayesian_pipeline()/run_llm_pipeline()/ assign_taxa_llm(), but can misclassify a hand-built or third-party result that happens to share (or omit) those column names. Pass this explicitly to avoid relying on the guess. Ignored when consensus comes from score_consensus (workflow is always "score" in that case, not a guess). |
| data_type | no | NULL | Character. One of "eDNA", "image", "acoustic", or NULL. Used to tailor methods language. |
| marker | no | NULL | Character. Molecular marker name (e.g. "12S MiFish"). Used only when data_type = "eDNA". |
| context_source | no | "user" | Character. One of "user" (user provided geographic context manually) or "llm" (context was inferred by build_context). Affects the methods description of how geographic context was determined. Default "user". |
| study_description | no | NULL | Character. One or two sentences describing the study context, passed to the LLM to ground the results narrative. |
| llm_fn | no | NULL | Function or NULL. LLM provider function following the TaxaTools llm_fn pattern. When NULL, the Results section uses a template-based bullet-point summary instead of LLM prose. |
| verbose | no | FALSE | Logical. Print progress messages. Default FALSE. |

**Value:** A single character string containing markdown-formatted Methods and Results text. Printed to the console via 'cat()' and returned invisibly.

### join_priors(likelihoods, taxaexpect_priors, site = NULL, taxonomy_lookup = NULL, rank_system = NULL, expansion_taxonomy = NULL, expansion_min_prior = 0.05, expansion_cumulative_prior = 0.9, singleton_taxonomy = NULL, backbone_id)

Join Likelihoods to TaxaExpect Priors

Bridges the gap between TaxaLikely likelihoods and 'compute_posterior()': maps each 'observation_id' to a site, joins occurrence-based priors from TaxaExpect, applies a dark diversity fallback for species with no modelled prior, deduplicates, fills missing taxonomy columns, and removes redundant higher-rank hypotheses.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihoods | yes |  | Data frame of likelihoods, typically from TaxaLikely::apply_coverage_constraints() or TaxaLikely::expand_unreferenced_hypotheses(). Must contain observation_id, taxon_name, taxon_name_rank. |
| taxaexpect_priors | yes |  | Data frame of TaxaExpect priors. One row per taxon_name x grid_id x main_habitat, with columns alpha, beta, undetected_type, and taxonomy columns (genus, family, etc.). |
| site | no | NULL | Site specification including habitat. main_habitat is always required -- the function does not guess which habitat your observations came from. Accepted formats: Named list with lat/lon: list(lat = 34.1, lon = -119.1, main_habitat = "Marine") -- auto-resolves to nearest grid_id. Named list with grid_id: list(grid_id = "...", main_habitat = "Marine") Data frame (multi-site): Columns observation_id, grid_id, main_habitat. Or observation_id, lat, lon, main_habitat. If main_habitat is omitted, the error message lists available habitats and row counts at the resolved grid cell. list(main_habitat = "Marine") alone (no lat/lon/ grid_id) auto-fills coordinates from attr(taxaexpect_priors, "search_center") when present -- set by the archived TaxaExpect::build_priors() (GLMM chain, archived 2026-09-09; only relevant for an old cached build_priors() result you still have on disk, since estimate_kernel_priors() does not set this attribute) -- main_habitat itself is never auto-filled or guessed. See Details. |
| taxonomy_lookup | no | NULL | Optional data frame mapping taxon_name to taxonomy columns (e.g. genus, family). Used to fill taxonomy for species that have likelihoods but are absent from taxaexpect_priors. Typically built from match_df columns. Default NULL (no external taxonomy fill). |
| rank_system | no | NULL | Character vector of taxonomic ranks from coarsest to finest. Passed to TaxaMatch::filter_redundant_hypotheses(). Default NULL auto-detects from columns in likelihoods. |
| expansion_taxonomy | no | NULL | Optional data frame mapping species names in taxaexpect_priors to their higher-rank taxonomy. Must contain taxon_name plus one or more coarser-rank columns (e.g. genus, family). Typically produced by TaxaTools::fill_higher_ranks(unique(taxaexpect_priors$taxon_name), local_sources = list(match_df)). When NULL (default) and coarse-rank likelihood rows are present, a warning is emitted and those rows fall back to the dark diversity floor prior. See Details. |
| expansion_min_prior | no | 0.05 | Numeric in [0, 1). Minimum normalized prior (within the coarse-rank candidate set) for a species to be included in the expansion. Mirrors min_posterior in posterior_consensus(). Default 0.05. |
| expansion_cumulative_prior | no | 0.9 | Numeric in (0, 1]. Cumulative prior threshold for the expansion candidate set. Species are added in descending prior order until this fraction of the within-constraint prior mass is reached. Mirrors cumulative_threshold in posterior_consensus(). Default 0.90. |
| singleton_taxonomy | no | NULL | Optional data frame mapping taxon_name to taxonomy columns (genus, family, order, class, phylum). When supplied, unmodelled candidates (those with no TaxaExpect prior) receive mass-conserving hierarchical group priors instead of the flat global-floor prior. Groups are formed by descending phylum -> class -> order -> family -> genus: sub-clades with zero singleton mirrors form a single combined group (budget = 1 x parent-clade singleton mean / n_candidates); sub-clades with >= 1 singleton mirrors subdivide further; genus is terminal. Concentration phi = effective_singletons * singleton_ess (2). Adds three diagnostic columns to output: dark_diversity_group, n_singletons_group, n_undetected_group. Typically the same data frame passed as taxonomy to generate_undetected_diversity() (built from occurrences_std). Default NULL (flat global-floor for all unmodelled candidates). |
| backbone_id | yes |  | Taxonomic backbone ID used for the taxonomy fallback fill (see Details). Required, no default -- the correct value depends on which backbone your input taxonomy was verified against, which varies by project. Passed straight through to TaxaTools::verify_taxon_names()/TaxaTools::change_backbone()'s dataSources ID (see https://verifier.globalnames.org/ for the full list). Common values: 1 Catalogue of Life, 3 ITIS, 4 NCBI, 9 WoRMS, 11 GBIF. |

**Value:** A data frame ready for 'compute_posterior()', with columns 'prior_mean', 'prior_alpha', and 'prior_beta' added. All input columns are preserved. Additional columns from 'taxaexpect_priors' (e.g. 'alpha', 'beta', 'model_tier') are included from the join.

### posterior_consensus(posterior_df, rank_system = NULL, cumulative_threshold = 0.9, min_posterior = 0.05, posterior_col = "posterior_point_est", lookup_missing_taxonomy = FALSE, backbone_id = NULL, species_reference = NULL, downrank_requires_candidate = TRUE, group_priors = NULL, min_effective_records = 0)

Derive Consensus Taxonomy from a Posterior Dataframe

For each 'observation_id', identifies the minimal set of top-ranked hypotheses that together account for 'cumulative_threshold' of the named-taxon posterior mass (after excluding hypotheses below 'min_posterior'), then returns their lowest common ancestor (LCA) as the consensus taxonomic assignment.

| Param | Required | Default | Doc |
|---|---|---|---|
| posterior_df | yes |  | Dataframe. Output of compute_posterior() or assign_taxa_llm(). Required columns: observation_id, taxon_name, taxon_name_rank, hypothesis_type, and the column named by posterior_col. |
| rank_system | no | NULL | Optional character vector of taxonomy column names, coarse-to-fine (e.g. c("family", "genus", "species")). If NULL (default), standard taxonomy columns present in posterior_df are detected automatically from kingdom, phylum, class, order, family, genus, species. Genus is always derivable from species binomials even when the genus column is absent. |
| cumulative_threshold | no | 0.9 | Numeric in (0, 1]. Cumulative posterior probability threshold for the plausible hypothesis set. Hypotheses are included in descending posterior order until this fraction of total probability is reached. At 0.90, the plausible set contains the fewest hypotheses accounting for at least 90% of posterior mass, analogous to a 90% credible interval. Default 0.9. For example, at 0.9 with posteriors (0.6, 0.25, 0.10, 0.05), the plausible set includes the top 2 hypotheses (0.6 + 0.25 = 0.85 < 0.9, so the third is also included: 0.6 + 0.25 + 0.10 = 0.95 >= 0.9). The LCA of these three hypotheses becomes the consensus. |
| min_posterior | no | 0.05 | Numeric in [0, 1). Minimum individual posterior probability to retain a hypothesis. Hypotheses below this threshold are excluded before computing the LCA consensus. At 0.05, a hypothesis must hold at least 5% posterior probability to influence the consensus taxon. Default 0.05. Set to 0 to disable. |
| posterior_col | no | "posterior_point_est" | Character. Name of the posterior column to rank hypotheses by. Default "posterior_point_est" -- aligned (2026-08-28) with run_bayesian_pipeline() and every production workflow, which had always passed the point-estimate column explicitly while this function alone defaulted to "posterior_mean" (undocumented drift; the three-way operative-column experiment in ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md (D8) found the choice second-order and settled on point estimates: best external corroboration, deterministic, and exactly auditable as prior x likelihood products). Pass "posterior_mean" to rank by the Monte Carlo mean instead -- with presence-mixture priors that column integrates over presence states (see compute_posterior()). |
| lookup_missing_taxonomy | no | FALSE | Logical. If TRUE, calls TaxaTools::verify_taxon_names() to fill in taxonomy columns for "unreferenced_species" rows that have NA in those columns. Requires TaxaTools to be installed and may make network requests. Default FALSE. |
| backbone_id | no | NULL | Integer. Taxonomic backbone to use when lookup_missing_taxonomy = TRUE. Passed to TaxaTools::verify_taxon_names(). Required (errors) when lookup_missing_taxonomy = TRUE -- no default, since the correct backbone depends on which backbone your input taxonomy was verified against, which varies by project. Common values: 1 = Catalogue of Life, 4 = NCBI, 9 = WoRMS, 11 = GBIF. See ecosystem CLAUDE.md for full list. Ignored (may be left NULL) when lookup_missing_taxonomy = FALSE. |
| species_reference | no | NULL | Optional. A plausible-species reference used to downrank unresolved coarse-rank consensus assignments. Accepts two forms: unreferenced_species_result (from TaxaLikely::suggest_unreferenced_species()): the full LLM-generated plausible species list is extracted automatically from attr(x, "plausible"). This includes referenced species (e.g. Leptocottus armatus) that the LLM flagged as plausible but that were filtered out of the unreferenced vector by the NCBI step. Use in the LLM workflow by passing the same object supplied to assign_taxa_llm(unreferenced_taxa = ...). data.frame: must contain a taxon_name column (species-level names) and columns named after each coarser rank in rank_system (e.g. genus, family). Pass taxaexpect_species_df in the Bayesian workflow. For each unresolved row where consensus_rank is not the finest rank, the function looks up how many taxa at the next finer rank belong to the consensus taxon. If exactly one, it downranks (recursively — e.g. family to unique genus to unique species in one pass). Stops at any rank with more than one option. Default NULL (no downranking). Since 2026-09-13 a narrowing must also survive downrank_requires_candidate. Callers building species_reference from a mix of observed and evidence-only rows should still exclude the evidence-only ones (prior_branch != "resident_observed") before passing it in, so a downrank reflects a species this observation could plausibly have produced, not merely one that is locally plausible in the abstract. |
| downrank_requires_candidate | no | TRUE | Logical. When TRUE (default), a downranking step is taken only if the reference's single finer taxon is at or above a taxon this observation actually scored (its plausible_taxa). A narrowing to a coarser-than-finest rank is kept when the candidates belong to it (family to genus Ulva when the candidates are Ulva species), so this is a taxonomy test, not a string match. Rows with no plausible_taxa column, or an empty one, are not gated. FALSE restores the pre-2026-09-13 behaviour, where the reference alone decided. Measured across four production sites before this gate: 35 of 150 downranked rows named a taxon outside their own candidate set. |
| group_priors | no | NULL | Optional data frame from compute_group_priors() (rank/taxon/theta_sum/n_members columns), the SUM of theta_mean over every locally modelled member of a genus or family -- not just the candidates one observation's own evidence happened to surface. Drives consensus_prior when a matching (rank, taxon) row exists for an observation's consensus_rank/consensus_taxon (see that column's own docs below for the full reasoning). Default NULL: consensus_prior is NA for every row -- there is no fallback computation (removed 2026-07-30; the previous candidate-scoped MAX was a real underestimate, not a safe approximation). |
| min_effective_records | no | 0 | Numeric, >= 0. Minimum effective_records a winning row must carry before winner_has_occurrence_record is allowed to read TRUE. Default 0 -- branch membership alone, which is exactly the pre-2026-09-14 behaviour, so no existing caller's output moves. Why this exists: TaxaExpect::estimate_kernel_priors() writes prior_branch as a CONSTANT on every row it emits, so the branch records which generator made the row, never how much evidence stands behind it. Within that one branch effective_records spans roughly ten orders of magnitude -- on the real PtConception 12S priors, 215 of 479 labelled rows (44.9%) carried under one Kish effective record, minimum 0.0000; at 18S, 987 of 1521 (64.9%); at GreatLakes only 17 of 90 (18.9%). Reading the label as an evidence claim therefore reports a quarter to two thirds of rows as having a local occurrence record on effectively no records at all, and that verdict feeds the published Axis-1 plausibility categories via TaxaFlag::add_posthoc_assessment(). No threshold is defaulted ON because there is no natural one: the distribution is continuous with no valley, so any cutoff is a judgment call that moves rows between plausibility categories and must be validated before it is trusted. One Kish effective record is the defensible starting point if you want one. Changing it from 0 WILL move winner_has_occurrence_record, and therefore the plausibility counts -- re-run the held-out GreatLakes/Lamar check (current benchmark: precision 0.872) before relying on the result. |

**Value:** A dataframe with one row per 'observation_id': 'observation_id' Sample identifier (same type as input). 'consensus_taxon' Name of the LCA taxon, or 'NA' if unresolvable (all hypotheses excluded or no rank agrees). 'consensus_rank' Rank of the LCA (e.g. '"genus"', '"family"'), or 'NA'. 'consensus_reason' How the consensus was reached: '"unanimous"' (all plausible hypotheses agree at the finest rank

### report_assign(result = NULL, consensus, data_type = NULL, workflow = NULL, verbose = FALSE)

Generate a Report Section for Taxonomic Assignment

Summarizes the taxonomic assignment results into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| result | no | NULL | Data frame or NULL. Posterior output from compute_posterior or assign_taxa_llm. Required for posterior-based consensus. Pass NULL for score-based. |
| consensus | yes |  | Data frame. Output from posterior_consensus or score_consensus. |
| data_type | no | NULL | Character or NULL. One of "eDNA", "image", "acoustic". |
| workflow | no | NULL | Character or NULL. One of "bayesian" or "llm" -- overrides the auto-detected workflow used to select Methods-text wording (same auto-detection caveat as generate_report's workflow argument: reliable for this package's own pipeline output, but can misclassify a hand-built or third-party result). Ignored when consensus comes from score_consensus (workflow is always "score"). |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing assignment method. results Template text summarizing assignment outcomes. params Named list of assignment parameters. statistics Named list of summary counts.

### run_bayesian_pipeline(match_df, model_params, taxaexpect_priors, site, rank_system = c("order", "family", "genus", "species"), model_rank_system = NULL, n_sims = 1000L, ratio_threshold = 0.01, barcode_term = "12S", unreferenced_df = NULL, constraint_behavior = c("relabel", "zero"), cumulative_threshold = 0.9, min_posterior = 0.05, posterior_col = "posterior_point_est", backbone_id, lookup_missing_taxonomy = TRUE, confirmation_quantile = 0.9, confirmation_discount = 0.25, species_reference = NULL, generate_report = FALSE, report_params = list(), llm_fn = NULL, verbose = TRUE)

Run the Full Bayesian Assignment Pipeline

High-level wrapper that chains TaxaLikely likelihoods + TaxaExpect priors through the full TaxaAssign Bayesian workflow: evaluate likelihoods, audit coverage, expand unreferenced hypotheses, join priors, compute posteriors, derive consensus, and refine via empirical Bayes.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Standardized match object from standardize_match_data, with columns observation_id, score, taxon_name, taxon_name_rank, and taxonomy columns. |
| model_params | yes |  | A taxa_model_params object from train_likelihood_model. |
| taxaexpect_priors | yes |  | Priors from TaxaExpect. Accepts either a data frame (from estimate_kernel_priors's $priors element, or historically generate_full_priors()) or a full list with a $priors element (the shape estimate_kernel_priors() itself returns, or the archived build_priors()'s output if you have one cached -- the $priors element is extracted automatically either way). |
| site | yes |  | Site context for prior joining, including habitat. main_habitat is always required — the function does not guess which habitat your observations came from. Accepted formats: Named list with lat/lon: list(lat = 34.1, lon = -119.1, main_habitat = "Marine") -- auto-resolves to nearest grid cell. Named list with grid_id: list(grid_id = "...", main_habitat = "...") Data frame (multi-site): Columns observation_id, grid_id, main_habitat -- OR -- observation_id, lat, lon, main_habitat. If main_habitat is omitted, the error message lists available habitats at the resolved grid cell so you can choose the right one. |
| rank_system | no | c("order", "family", "genus", "species") | Character vector of taxonomy ranks, coarse to fine. Used for taxonomy fill, prior join, and consensus LCA. Default c("order", "family", "genus", "species"). |
| model_rank_system | no | NULL | Character vector of ranks present in match_df (and the trained model). Used for evaluate_likelihoods() and filter_top_hypotheses(). Default NULL auto-detects from the intersection of rank_system and names(match_df). |
| n_sims | no | 1000L | Integer. Monte Carlo simulations for likelihood evaluation and posterior computation. Default 1000L. |
| ratio_threshold | no | 0.01 | Numeric. Minimum likelihood ratio for retaining hypotheses in evaluate_likelihoods(). Default 0.01. |
| barcode_term | no | "12S" | Character. Barcode marker for audit_barcode_coverage() when unreferenced_df is NULL. Default "12S". |
| unreferenced_df | no | NULL | Optional data frame of unreferenced species (columns species, genus, family). When NULL (default), unreferenced species are auto-detected via audit_barcode_coverage. Set to an empty data frame to skip unreferenced expansion entirely. |
| constraint_behavior | no | c("relabel", "zero") | Character. How to handle unreferenced species in fully-sampled genera: "relabel" (default) or "zero". Passed to apply_coverage_constraints. |
| cumulative_threshold | no | 0.9 | Numeric. Posterior probability threshold for consensus. Default 0.90. |
| min_posterior | no | 0.05 | Numeric. Minimum posterior to be considered plausible. Default 0.05. |
| posterior_col | no | "posterior_point_est" | Character. Column name for posterior values. Default "posterior_point_est". |
| backbone_id | yes |  | Integer. Backbone for taxonomy lookup in join_priors and consensus. Required, no default -- the correct value depends on which backbone your input taxonomy was verified against, which varies by project (e.g. 11 for GBIF, 4 for NCBI). See TaxaTools::verify_taxon_names()'s backbone_id docs, or https://verifier.globalnames.org/ for the full list. |
| lookup_missing_taxonomy | no | TRUE | Logical. Look up missing taxonomy in consensus. Default TRUE. |
| confirmation_quantile | no | 0.9 | Numeric in (0, 1]. Quantile of confirming observations' consensus_posterior used for the empirical Bayes prior boost of confirmed species. Default 0.9. See update_prior_from_consensus. |
| confirmation_discount | no | 0.25 | Numeric in [0, 1]. Power-prior discount on the cross-observation support mass in the soft confirmation update. Default 0.25; 0 disables the update. See update_prior_from_consensus. |
| species_reference | no | NULL | Optional. Passed to posterior_consensus for downranking. Accepts an unreferenced_species_result or data frame. |
| generate_report | no | FALSE | Logical. Generate a Methods + Results report. Default FALSE. |
| report_params | no | list() | Named list of additional arguments passed to generate_report (e.g. data_type, marker, study_description). |
| llm_fn | no | NULL | Optional function. LLM provider for report generation. Only used when generate_report = TRUE. Default NULL (template-only report, no LLM Results text). |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A named list with components: '$consensus' Final consensus data frame (one row per 'observation_id'), after empirical Bayes refinement. '$result' Full posterior data frame (after refinement), with all hypotheses per observation. '$coverage' Coverage audit result from 'audit_barcode_coverage()', or 'NULL' if 'unreferenced_df' was user-supplied. '$likelihoods' The expanded, constraint-applied likeli

### run_llm_pipeline(match_df, context = NULL, auto_context = TRUE, geographic_hint = NULL, date = NULL, habitat_scheme = NULL, llm_fn = NULL, detect_unreferenced = TRUE, barcode_term = "12S", expand_to_family = TRUE, max_date = NULL, unreferenced_taxa = NULL, score_threshold = 80, top_n = 10L, score_sharpness = 0.1, unknown_lik_weight = 0.05, known_present = NULL, known_absent = NULL, absent_detection_prob = 0.8, taxa_per_call = 15L, pause_seconds = 1, prior_phi = c(high = 50, moderate = 10, low = 3), n_sims = 1000L, context_group = NULL, rank_system = c("family", "genus", "species"), cumulative_threshold = 0.9, min_posterior = 0.05, posterior_col = "posterior_point_est", backbone_id, lookup_missing_taxonomy = TRUE, confirmation_quantile = 0.9, confirmation_discount = 0.25, generate_report = FALSE, report_params = list(), verbose = TRUE)

Run the Full LLM-Shortcut Assignment Pipeline

High-level wrapper that chains the LLM-shortcut workflow into a single call: optionally build context, optionally detect unreferenced species, run 'assign_taxa_llm()', derive consensus, refine via empirical Bayes, and optionally generate a report.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Standardized match object from standardize_match_data, with columns observation_id, score, taxon_name, taxon_name_rank, and taxonomy columns. |
| context | no | NULL | Optional data frame or list with location/habitat context. When NULL (default) and auto_context = TRUE, context is auto-populated via build_context. When supplied, passed directly to assign_taxa_llm. |
| auto_context | no | TRUE | Logical. When TRUE (default) and context is NULL, automatically build context via build_context. Requires the TaxaHabitat package. |
| geographic_hint | no | NULL | Optional character string for build_context (e.g. "Southern California"). Ignored when context is supplied. |
| date | no | NULL | Optional character string for build_context (e.g. "2025"). Ignored when context is supplied. |
| habitat_scheme | no | NULL | Passed to build_context for habitat assignment. Default NULL (3-category). |
| llm_fn | no | NULL | Function or NULL. LLM provider following the TaxaTools llm_fn pattern. Default NULL resolves to getOption("TaxaID.llm_fn") when set, otherwise TaxaTools::call_api (requires TaxaTools). |
| detect_unreferenced | no | TRUE | Logical. When TRUE (default), run suggest_unreferenced_species to detect taxa absent from the reference database (requires TaxaLikely). Set to FALSE to skip. |
| barcode_term | no | "12S" | Character. Barcode marker for unreferenced species detection. Default "12S". |
| expand_to_family | no | TRUE | Logical. Expand unreferenced search to family level. Default TRUE. Passed to suggest_unreferenced_species. |
| max_date | no | NULL | Optional character. NCBI date filter for unreferenced species detection (e.g. "2024/12/31"). |
| unreferenced_taxa | no | NULL | Optional character vector of known unreferenced species. When supplied, detect_unreferenced is ignored and these are passed directly to assign_taxa_llm. |
| score_threshold | no | 80 | Numeric. Minimum score to include a candidate (0-100). Default 80. |
| top_n | no | 10L | Integer. Maximum candidates per observation sent to LLM. Default 10. |
| score_sharpness | no | 0.1 | Numeric. Exponential weight sharpness for likelihood proxy. Default 0.1. |
| unknown_lik_weight | no | 0.05 | Numeric. Baseline likelihood for the unknown species hypothesis. Default 0.05. |
| known_present | no | NULL | Optional character vector of confirmed present species. |
| known_absent | no | NULL | Optional character vector or data frame of confirmed absent species. See assign_taxa_llm for details. |
| absent_detection_prob | no | 0.8 | Numeric. Detection probability for known-absent species. Default 0.80. |
| taxa_per_call | no | 15L | Integer. Maximum taxa per LLM call. Default 15 (lowered from 30 on 2026-07-09 -- see assign_taxa_llm's own taxa_per_call docs for the real truncation evidence behind this change). |
| pause_seconds | no | 1 | Numeric. Pause between LLM calls. Default 1. |
| prior_phi | no | c(high = 50, moderate = 10, low = 3) | Named numeric vector mapping information_quality to Beta concentration. Default c(high = 50, moderate = 10, low = 3). |
| n_sims | no | 1000L | Integer. Monte Carlo simulations. Default 1000L. |
| context_group | no | NULL | Optional character vector of column names in context for grouping observations. Default NULL. |
| rank_system | no | c("family", "genus", "species") | Character vector of taxonomy ranks, coarse to fine. Default c("family", "genus", "species"). |
| cumulative_threshold | no | 0.9 | Numeric. Posterior probability threshold for consensus. Default 0.90. |
| min_posterior | no | 0.05 | Numeric. Minimum posterior to be considered plausible. Default 0.05. |
| posterior_col | no | "posterior_point_est" | Character. Column name for posterior values. Default "posterior_point_est". |
| backbone_id | yes |  | Integer. Backbone for taxonomy lookup in consensus. Required, no default -- the correct value depends on which backbone your input taxonomy was verified against, which varies by project (e.g. 11 for GBIF, 4 for NCBI). See TaxaTools::verify_taxon_names()'s backbone_id docs, or https://verifier.globalnames.org/ for the full list. |
| lookup_missing_taxonomy | no | TRUE | Logical. Look up missing taxonomy in consensus. Default TRUE. |
| confirmation_quantile | no | 0.9 | Numeric in (0, 1]. Quantile of confirming observations' consensus_posterior used for the empirical Bayes prior boost of confirmed species. Default 0.9. See update_prior_from_consensus. |
| confirmation_discount | no | 0.25 | Numeric in [0, 1]. Power-prior discount on the cross-observation support mass in the soft confirmation update. Default 0.25; 0 disables the update. See update_prior_from_consensus. |
| generate_report | no | FALSE | Logical. Generate a Methods + Results report. Default FALSE. |
| report_params | no | list() | Named list of additional arguments passed to generate_report (e.g. data_type, marker, study_description). |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A named list with components: '$consensus' Final consensus data frame (one row per 'observation_id'), after empirical Bayes refinement. '$result' Full posterior data frame (after refinement), with all hypotheses per observation. '$context' The context data frame used (auto-built or user-supplied). '$unreferenced' The unreferenced species result, or 'NULL' if skipped. '$report' Report text from 'ge

### score_consensus(match_df, min_score = 0, max_gap = Inf, whitelist = NULL, score_col = "score_original", rank_system = NULL, rank_thresholds, consensus_mode = c("gap", "bracket"), agreement_fraction = 1, bracket_width = 1, bracket_fallback = NULL)

Derive Consensus Taxonomy from Raw Match Scores

For each 'observation_id', applies conventional score-based filtering to derive a consensus taxonomic assignment. Two conventional decision rules are available, selected by 'consensus_mode'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. One row per observation_id x reference hit. Required columns: observation_id, taxon_name, taxon_name_rank, and the column named by score_col. Taxonomy columns (e.g. family, genus, species) are used for LCA resolution when present; genus is always derivable from species binomials. |
| min_score | no | 0 | Numeric. Minimum score to retain a hit. Hits below this value are discarded before any other filtering. Scale must match the score_col values (e.g. 97 for percent identity, 0.97 for proportion). Default 0 (no filtering). Note: an ROC-style sweep against real 12S reference data (diagnostics/score_floor_roc_sweep.R, 2026-07-09) found that min_score/raw percent-identity alone cannot discriminate a true species from its closest congener at almost any real-world threshold (true-positive and congeneric-false-positive rates track each other almost exactly up to ~97). min_score's real value is excluding obviously-wrong cross-family hits, not fine species-level discrimination -- that discrimination is rank_thresholds' job (see below). |
| max_gap | no | Inf | Numeric. Maximum score difference from the top hit (per sample). All hits within max_gap of the best score contribute to the LCA. For example, max_gap = 1 keeps all hits within 1 unit of the top score. Default Inf (all hits above min_score contribute). |
| whitelist | no | NULL | Character vector or NULL. Plausible taxon names (any rank). When supplied, the consensus taxon must appear in this list; otherwise the consensus is upranked to the coarsest rank where a whitelist member agrees with the retained candidates. Default NULL (no whitelist filtering). |
| score_col | no | "score_original" | Character. Column name containing match scores. Default "score_original". |
| rank_system | no | NULL | Character vector of taxonomy column names, coarse to fine (e.g. c("family", "genus", "species")). If NULL (default), standard columns present in match_df are detected automatically. |
| rank_thresholds | yes |  | Named numeric vector, or NULL. Maps rank names to minimum scores, e.g. c(species = 97, genus = 95, family = 90). After the LCA is computed, the consensus is capped at the finest rank whose threshold the top score meets. If the top score fails all thresholds, the sample is unresolvable. Applied independently of the LCA — so even if all hits agree on species, the consensus is demoted to genus if the top score is below the species threshold. No default -- errors if omitted (2026-07-23). This function has no way to know the marker or even whether score_col holds a DNA/image/ acoustic score, so no single fixed threshold set is safe to assume for every caller (see Details for why the earlier GITA/Jonah Ventures default, c(species = 98, genus = 95, family = 90, phylum = 85), was removed rather than kept as a default). Supply one of: (1) your own thresholds, on whichever scale score_col uses (percent identity or 0-1 proportion -- see the auto-rescale note below), or (2) marker-specific thresholds derived from your own reference data via TaxaLikely::compute_rank_thresholds() (per-rank Youden's J on a build_sequence_matrix()-style pairwise distance matrix). Pass rank_thresholds = NULL explicitly to disable rank capping entirely. If score_col's values look like a 0-1 proportion scale (max <= 1) rather than 0-100 percent-identity, a supplied 0-100-scale rank_thresholds is automatically rescaled by /100 (with an informational message) -- pass your own already-scaled rank_thresholds to silence this. |
| consensus_mode | no | c("gap", "bracket") | Character, one of "gap" (default) or "bracket". "gap" is the pre-2026-09-12 behaviour exactly: min_score floor -> max_gap window -> LCA over the distinct retained taxa. "bracket" selects the Jonah Ventures rule: min_score floor -> a bracket_width window anchored at the top score -> agreement rule over the retained hits (not distinct taxa -- JV's rule counts hits). max_gap is ignored in "bracket" mode; bracket_width/bracket_fallback are ignored in "gap" mode. |
| agreement_fraction | no | 1 | Numeric in (0, 1]. A taxon is reported at a rank when it appears in at least this fraction of the retained rows. 1 (default) is strict unanimity, i.e. a classical LCA. Jonah Ventures uses 0.9. Applies in both modes: in "gap" mode it generalises the LCA step, and agreement_fraction = 1 there is byte-for-byte the pre-2026-09-12 result. The comparison is inclusive at the boundary (9 of 10 rows resolves at agreement_fraction = 0.9), and is made with a small floating-point tolerance so that e.g. 27/30 >= 0.9 cannot fail on binary representation. If two or more taxa clear the bar at the same rank (possible only when agreement_fraction <= 0.5), NA is reported at that rank rather than an arbitrary winner -- JV: "If several taxa within a taxonomic level match the ESV, an NA is reported for that taxonomic level." Rows whose label at a rank is missing count toward the denominator, not toward any taxon. A hit with no family assigned is evidence against a family-level consensus, not a row to be quietly dropped; dropping it would inflate agreement, and JV's own delivered output contains NA ranks. |
| bracket_width | no | 1 | Numeric, positive. Width of the score bracket in score_col's own units. Jonah Ventures uses 1 (one percent-identity point), which is the default. Hits scoring in (top - bracket_width, top] are retained. Only used when consensus_mode = "bracket". The lower bound is exclusive, and Jonah Ventures' own is not (found 2026-09-12 while validating against their delivered Pt Conception MiFish taxonomy -- diagnostics/jv_bracket_consensus_validation.R). Their delivered detailed-hit tables do contain hits at exactly top - 1, and those hits demonstrably contributed to their published consensus, so their real interval is the closed [top - 1, top]. The exclusive bound implemented here is the documented published description read literally. It matters for 1 ESV in 14,719 across both Pt Conception MiFish runs, so it is left as specified rather than quietly widened; pass bracket_width = 1 + 1e-6 for the closed-interval behaviour. |
| bracket_fallback | no | NULL | NULL (default, no fallback) or a named list with elements min_score, rank and width describing a widen-the-bracket rule. Jonah Ventures' published rule is list(min_score = 97, rank = "family", width = 2): if the top score is at least min_score and the bracket produced no taxonomy at rank or finer (i.e. no family-level name would be printed), the observation is recomputed with a bracket of width width. Only used when consensus_mode = "bracket". Widening is not monotone in resolution: adding hits usually dilutes agreement, but it can also break a tie in favour of one label (e.g. a 1:1 split at 1% becoming 1:19 at 2%), which is the case in which the fallback actually rescues a family-level call. The widened result replaces the narrow one whenever the fallback fires, whether or not it resolved -- bracket_width_used records which bracket produced the row. |

**Value:** A data frame with one row per 'observation_id': 'observation_id' Sample identifier. 'consensus_taxon' LCA taxon name, or 'NA' if unresolvable. 'consensus_rank' Rank of the LCA (e.g. '"genus"'), or 'NA'. 'consensus_reason' How the consensus was reached: '"unanimous"' (all retained taxa agree at the finest rank), '"single"' (only one taxon retained after filtering), '"lca"' (upranked because retaine

### suggest_unreferenced_species(...)

Suggest Unreferenced Species Using an LLM (deprecated - moved to TaxaLikely)

*Deprecated.* This function has moved to 'TaxaLikely::suggest_unreferenced_species()' - see that function's documentation for the full parameter list, algorithm, and return-value description. This wrapper forwards every argument unchanged and exists only so that a caller who hasn't yet updated to 'TaxaLikely::suggest_unreferenced_species()' still gets a working call (with a deprecation warning) instead of a hard failure.

| Param | Required | Default | Doc |
|---|---|---|---|
| ... | yes |  | Forwarded unchanged to TaxaLikely::suggest_unreferenced_species(). |

**Value:** See 'TaxaLikely::suggest_unreferenced_species()'.

### update_prior_from_consensus(result, consensus, confirmation_quantile = 0.9, confirmation_discount = 0.25, n_sims = 0, spatial_group_map = NULL)

Update Priors from Consensus Assignments and Recompute Posteriors

A one-pass empirical Bayes refinement step. Every observation's posterior support for a species is treated as fractional evidence of site-level presence (soft assignment - no confirmation threshold), aggregated with a leave-one-out, power-prior-discounted mass, and used to move unresolved observations' priors smoothly toward a support-weighted confirmation quantile (never lowering them); 'compute_posterior()' is then re-run for those observations only. See the _Soft confirmation_ section for the design and its literature grounding.

| Param | Required | Default | Doc |
|---|---|---|---|
| result | yes |  | Dataframe. Output of assign_taxa_llm() or compute_posterior(). Must contain: observation_id, taxon_name, score_likelihood, score_likelihood_mean, score_likelihood_sd, prior_mean. When prior_alpha/prior_beta (Beta shape parameters) are present, they are recomputed alongside prior_mean for boosted rows, preserving the original concentration (alpha + beta) so compute_posterior()'s Monte Carlo path stays consistent with the boosted point estimate -- fixes a latent inconsistency in the previous design, where only prior_mean was rescaled and a stale Beta shape could be sampled from if n_sims > 0. |
| consensus | yes |  | Dataframe. Output of posterior_consensus() run on result. Must contain: observation_id, consensus_taxon, is_resolved, consensus_posterior. |
| confirmation_quantile | no | 0.9 | Numeric in (0, 1]. Quantile of confirming observations' consensus_posterior used as the candidate new prior_mean for a confirmed species. Default 0.9. 1 is equivalent to taking the maximum. |
| confirmation_discount | no | 0.25 | Numeric in [0, 1]. Power-prior discount a0 applied to the cross-observation support mass (0.25 default: ~4 correlated observations carry the weight of 1 independent one; 0 disables the update entirely; 1 treats every observation as fully independent -- almost certainly too strong for same-site eDNA). See the Soft confirmation section. |
| n_sims | no | 0 | Integer. Passed to compute_posterior() for the re-run. Default 0 (point estimates only, fast). Set to 1000 to propagate uncertainty — match the value used in the original run. |
| spatial_group_map | no | NULL | Dataframe with observation_id and spatial_group_id columns (e.g. from TaxaMatch::group_observations_by_bbox()), optional. When supplied, only observations whose spatial_group_id is shared with at least one other observation can contribute confirmed species or receive a prior update; observations in a single-observation spatial group (a singleton spatial_group_id -- there is no separate naming convention for these, see group_observations_by_bbox()) are always returned unchanged. Default NULL (no group-based restriction — all observations participate, matching this function's original behaviour). Membership is binary (same group or not), with no distance decay within a group -- two sites 100 km apart placed in different spatial groups donate nothing to each other by design, exactly as if they were in the same group but 1 km apart they would donate at full weight. |

**Value:** The full posterior dataframe with the same structure as 'result', plus one new column, 'confirmed_without_occurrence_record' (logical, 'FALSE' unless set 'TRUE' - see @section Confirmed without an occurrence record). Resolved observations are returned unchanged. Unresolved observations in a multi-member spatial group (see 'spatial_group_map') have updated 'prior_mean' and freshly computed posterio

## Quick Start

### Full Bayesian workflow (recommended)

``` r
out <- run_bayesian_pipeline(
  match_df          = match_obj,         # from TaxaMatch
  model_params      = trained_model,     # from TaxaLikely
  taxaexpect_priors = priors,            # from TaxaExpect
  site = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine")
)
head(out$consensus)
```

### LLM-shortcut workflow (fast approximation -- no trained model/priors needed)

``` r
library(TaxaAssign)

out <- run_llm_pipeline(
  match_df        = match_obj,      # from TaxaMatch
  geographic_hint = "Southern California",
  barcode_term    = "12S"
)
head(out$consensus)
```

### Step-by-step

``` r
# 1. Join priors to likelihood output
joined <- join_priors(likelihoods, priors,
                      site = list(grid_id = "G1", main_habitat = "Marine"))

# 2. Compute posteriors via Monte Carlo
posteriors <- compute_posterior(joined, n_sims = 1000)

# 3. Consensus taxonomy (LCA among plausible hypotheses)
consensus <- posterior_consensus(posteriors)

# 4. Generate report
report <- generate_report(posteriors, consensus)
```

