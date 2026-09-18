# CONTEXT: TaxaLikely

**Convert Match Scores to Likelihoods for Taxonomic Assignment**

Trains a hierarchical Bayesian model on reference-vs-reference match scores (DNA percent identity, image similarity, acoustic scores) and uses it to convert per-observation match scores into likelihoods. For each observation (observation_id), produces score_likelihood, score_likelihood_mean, and score_likelihood_sd across candidate taxa - the columns required by TaxaAssign. Also provides reference database quality tools: detecting mislabeled references and auditing taxonomic completeness. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-15 11:58:40 UTC; unix). 33 exported function(s).

## Functions

### apply_coverage_constraints(likelihood_df, census_result, penalty_factor = 0, constraint_behavior = c("relabel", "zero"))

Apply taxonomic completeness constraints to likelihood results

Suppresses or relabels the '"unreferenced_species"' hypothesis for genera confirmed to be fully sampled in the reference database. If a genus has no unsampled species, a new undescribed species from that genus is impossible - so the '"unreferenced_species"' likelihood should either be zeroed (hard constraint) or relabeled to capture the alternative biology.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_df | yes |  | Data frame returned by 'evaluate_likelihoods()'. |
| census_result | yes |  | Data frame with columns 'taxon_name' (the group name, e.g. genus label), 'rank' (e.g. '"genus"'), and 'status' ('"complete"' or '"closed"' for fully-sampled groups; any other value leaves the hypothesis untouched). To build this from 'audit_barcode_coverage()': cov <- audit_barcode_coverage(match_df, barcode_term = "12S", target_rank = "genus") census_result <- dplyr::mutate( cov$census, taxon_name = group, rank = "genus", status = ifelse(is_complete, "complete", "incomplete") ) |
| penalty_factor | no | 0 | Numeric in [0, 1] (default '0.0'). Multiplier applied to 'score_likelihood' and 'score_likelihood_mean' for constrained hypotheses when 'constraint_behavior = "zero"'. Ignored when 'constraint_behavior = "relabel"' (the default). |
| constraint_behavior | no | c("relabel", "zero") | Character scalar: '"relabel"' (default) or '"zero"'. See Details above and "Census confidence" below. |

**Value:** 'likelihood_df' with an added 'constraint_applied' column and updated likelihood and/or 'hypothesis_type' columns: '"zero"' mode 'score_likelihood' and 'score_likelihood_mean' multiplied by 'penalty_factor'; 'constraint_applied' set to '"census_closed_genus"'. '"relabel"' mode 'hypothesis_type' changed to '"unresolved_species"'; likelihoods unchanged; 'constraint_applied' set to '"census_closed_ge

### assign_scores(hypotheses_df, score_type, score_col = "score_original", score_sharpness = 0.1)

Assign score_likelihood values to a hypotheses data frame

Converts raw match scores (or absence of scores) into the 'score_likelihood' column required by 'TaxaAssign::compute_posterior()'. Works on the expanded hypotheses data frame produced by 'unreferenced_candidates()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| hypotheses_df | yes |  | Data frame produced by 'unreferenced_candidates()'. Must contain 'observation_id' and 'hypothesis_type'. For all 'score_type' values except '"none"', must also contain the column named by 'score_col' for '"specific_candidate"' rows. |
| score_type | yes |  | Character scalar. One of '"none"', '"direct"', '"probability"', '"similarity_softmax"', or '"similarity"'. |
| score_col | no | "score_original" | Character. Name of the raw score column in 'hypotheses_df' (default '"score_original"'). Ignored when 'score_type = "none"'. |
| score_sharpness | no | 0.1 | Positive numeric (default '0.1'). Exponent scaling factor for 'score_type = "similarity_softmax"' only. Larger values create sharper discrimination between candidates; smaller values produce more uniform likelihoods. |

**Value:** For 'score_type = "similarity"': the input data frame with 'score_norm' (H1 rows only) and 'score_method = "similarity"' added. See the '"similarity"' entry under '@details' above - real callers use 'evaluate_likelihoods()' directly instead of continuing from this output. For all other 'score_type' values: a data frame with one row per 'observation_id' x hypothesis (H1 aggregated to one row per 't

### audit_acoustic_coverage(plausible_species, reference_species, match_df = NULL, xc_recordings = FALSE)

Audit Acoustic Reference Coverage for a Species List

Checks which plausible species at a site are absent from an acoustic classifier's known species list (e.g., BirdNET's built-in list or a custom Xeno-canto model). A species absent from the reference can never appear as a scored candidate - it is an *unreferenced species* in the acoustic context.

| Param | Required | Default | Doc |
|---|---|---|---|
| plausible_species | yes |  | Character vector. Species expected to occur at the sampling site (e.g., from an LLM call, GBIF query, or expert list). Should be binomial scientific names. |
| reference_species | yes |  | Character vector. Species in the classifier's known list (e.g., the BirdNET species list, or the set of species used to train a custom Xeno-canto model). Names are matched case-insensitively after trimming whitespace. |
| match_df | no | NULL | Data frame or 'NULL'. Optional. If supplied, species already present in the match data (i.e., confirmed candidates from the classifier) are annotated as 'in_match_data = TRUE' in the census output. Use 'TaxaMatch::standardize_match_data()' output or raw 'TaxaMatch::read_birdnet_output()' output. The species column is auto-detected from '"species"' or '"taxon_name"'. Default 'NULL'. |
| xc_recordings | no | FALSE | Logical. If 'TRUE', queries the Xeno-canto v3 API for the number of recordings available for each species in 'plausible_species' and adds an 'n_recordings' column to the census. Requires an internet connection, a registered Xeno-canto API key set via the 'XC_API_KEY' environment variable (register at xeno-canto.org/explore/api), and adds approximately 1 second per species. Default 'FALSE'. |

**Value:** A named list with two components: 'census' Data frame with one row per entry in 'plausible_species': 'species' Species name (from 'plausible_species'). 'in_reference' Logical. 'TRUE' if the species is in 'reference_species'. 'unreferenced' Logical. 'TRUE' if the species is absent from 'reference_species' (can never appear as a candidate detection). 'in_match_data' Logical. 'TRUE' if the species ap

### audit_barcode_coverage(match_df, barcode_term, species_list = NULL, min_len = NULL, max_len = NULL, max_date = NULL, target_rank = "genus", cache_dir = tools::R_user_dir("TaxaLikely", "cache"), ncbi_api_key = NULL, max_nuccore = 5000L, exclude_predicted = TRUE)

Identify unreferenced species for barcode-based taxonomic assignment

An *unreferenced species* is a described taxon that has *no barcode sequence* for the target marker in any reference database. Because TaxaMatch can only return taxa that have reference sequences, an unreferenced species can never appear as a named match candidate - even if it is the true source of the observed sequence. Adding unreferenced species as explicit hypotheses allows the LLM (via 'TaxaAssign::assign_taxa_llm()') to evaluate their geographic plausibility alongside the named match candidates.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame with at least a 'target_rank' column (e.g. '"genus"') and a '"species"' column. Species present in 'match_df' are treated as a *skip-list*: they have reference sequences by definition and are excluded from the barcode-count queries. Pass the actual match object (e.g. 'match_obj' / 'match_obj_restored' from 'restore_suppressed_candidates()') here - *not* a length-curated 'reference_df' built for 'build_sequence_matrix()'/'train_likelihood_model()'. A species whose only reference sequence is a long record (e.g. a complete mitogenome) is routinely dropped from a length-curated training set even though BLAST matched it correctly; passing that curated set here makes 'audit_barcode_coverage()' report the species "unreferenced" despite it already being a specific_candidate. See 'Details'. |
| barcode_term | yes |  | Character scalar or vector. One or more marker search terms (e.g. '"12S"', 'c("12S", "MiFish")'). Multiple terms are OR-ed. |
| species_list | no | NULL | Optional character vector of binomial species names. If supplied, used instead of the NCBI taxonomy query to determine which species exist in each genus. Useful when GBIF, FishBase, or WoRMS provides more complete coverage than NCBI taxonomy for your taxon group. Invalid names (sp., cf., uncultured, etc.) are silently dropped. min_len: Integer or NULL. Minimum sequence length ('SLEN' filter). NULL uses a barcode-specific default (see Details). max_len: Integer or NULL. Maximum sequence length. NULL uses the barcode-specific default. |
| min_len | no | NULL |  |
| max_len | no | NULL |  |
| max_date | no | NULL | Optional character scalar. Restricts unreferenced species detection to sequences present in NCBI on or before this date, embedded as a [PDAT] range in the query term. Format: '"YYYY"', '"YYYY/MM"', or '"YYYY/MM/DD"'. NULL uses the current state of GenBank. Set this to match the build date of your reference library. |
| target_rank | no | "genus" | Character scalar. Rank column in 'match_df' (default '"genus"'). |
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Directory for per-genus checkpoints. Default: 'tools::R_user_dir("TaxaLikely", "cache")'. Pass 'NULL' to disable checkpointing. If a checkpoint from a previous interrupted run is found (matched by call signature), processing resumes automatically from where it stopped. The checkpoint is deleted on clean completion. |
| ncbi_api_key | no | NULL | Optional NCBI API key. Raises the rate limit from 3 to 10 requests per second. Can also be set via 'ENTREZ_KEY' environment variable ('Sys.setenv(ENTREZ_KEY = "your_key")'; confirm with 'Sys.getenv("ENTREZ_KEY")'). |
| max_nuccore | no | 5000L | Integer. Maximum NCBI nucleotide IDs fetched per genus for the reverse barcode check. Default 5000; increase for extremely sequence-rich genera if some represented species are suspected to be missed. |
| exclude_predicted | no | TRUE | Logical. If 'TRUE' (default), computationally predicted sequences (NCBI title prefix '"PREDICTED:"', typically 'XR_' and 'XM_' RefSeq accessions) are excluded from the barcode check. Predicted sequences are absent from curated databases (SILVA, PR2, MIDORI) used by metabarcoding labs and do not represent experimentally validated barcodes - counting them inflates 'has_seqs_not_in_ref' and incorrectly suppresses unreferenced-species hypotheses for those taxa. Set 'FALSE' only if you explicitly need to count predicted sequences. Mirrors the 'blacklist_regex = "predicted"' default in 'fetch_ncbi_reference_sequences()'. |

**Value:** A named list: 'census' Data frame, one row per genus: 'group', 'total' (described species), 'in_reference' (in 'match_df'), 'has_seqs_not_in_ref' (experimental barcode sequences exist in NCBI but not in the reference - a completeness gap), 'has_predicted_only' (only computationally predicted sequences found; 'NA' when classification was not performed), 'unreferenced' (no barcode sequences found; w

### audit_inat_coverage(species_list, match_df = NULL, cv_threshold = 100L, api_token = Sys.getenv("INAT_API_TOKEN"), verbose = FALSE)

Audit iNaturalist Reference Coverage for a Species List

For each species in 'species_list', queries the iNaturalist taxa API to retrieve the global observation count and determine whether the species is likely present in iNaturalist's computer vision (CV) training data. Species with fewer than 'cv_threshold' observations are treated as *unreferenced* for the image classification pathway - they can never appear as CV candidates and must be handled as undetected taxa in 'TaxaAssign::join_priors()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| species_list | yes |  | Character vector. Species names to check (typically the set of prior taxa, or prior taxa absent from the match object). Non-binomial names are silently skipped. |
| match_df | no | NULL | Data frame or 'NULL'. Optional. If supplied, species already present in the image match data are annotated as 'in_match_data = TRUE'. The species column is auto-detected from '"taxon_name"' or '"species"'. Default 'NULL'. |
| cv_threshold | no | 100L | Integer. Minimum global observation count on iNaturalist for a species to be considered present in the CV training data. Default '100L'. The exact iNaturalist threshold is not publicly documented; 100 research-grade observations is a widely cited approximation. Species below this threshold are flagged 'cv_model_included = FALSE' and included in '$unreferenced'. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. Optional iNaturalist API token. When provided, increases the API rate limit. Defaults to 'INAT_API_TOKEN' environment variable; pass 'api_token = ""' to query without authentication. verbose: Logical. If 'TRUE', prints a progress line for each species. Default 'FALSE'. |
| verbose | no | FALSE |  |

**Value:** A named list with two components: 'census' Data frame with one row per entry in 'species_list', containing: 'species', 'taxon_id', 'matched_name' (iNat accepted name), 'n_observations' (global iNat count), 'in_inat' (logical; species found in iNat), 'cv_model_included' (logical; 'n_observations >= cv_threshold'), 'unreferenced' (logical; 'TRUE' when absent from iNat or below the CV threshold), 'in

### audit_reference_coverage(reference_df, target_rank = "genus", ncbi_api_key = NULL)

Audit reference database taxonomic completeness via NCBI taxonomy

For each group at 'target_rank' (e.g., each genus) in the reference database, queries the NCBI taxonomy database to count how many accepted species exist, then compares with the species present in your reference. Returns a census summary and a vector of unreferenced species - taxa known to exist at NCBI but absent from your reference.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame containing at least two columns: one named 'target_rank' (e.g., '"genus"') and one named '"species"'. |
| target_rank | no | "genus" | Character scalar - the rank to audit (default '"genus"'). Must be a column in 'reference_df'. |
| ncbi_api_key | no | NULL | Optional NCBI API key string (increases rate limit from 3 to 10 requests/second). Can also be set via the 'ENTREZ_KEY' environment variable before calling this function. |

**Value:** A named list: 'census' Data frame with one row per group: 'group', 'total' (true species count per NCBI), 'have' (in reference), 'missing_count', and 'is_complete' (logical). 'unreferenced' Character vector of species names present at NCBI but absent from the reference.

### build_sequence_matrix(reference_df, rank_system = NULL, max_dist = 0.25, min_seq_len = 100L, max_seq_len = 2000L, filter_unnamed = TRUE, max_seqs_per_taxon = NULL, barcode_term = NULL, verbose = TRUE, by_genus = FALSE, max_foreign_reps_per_genus = 20L)

Build a pairwise match-score matrix from reference sequences

Aligns DNA sequences using 'DECIPHER::AlignSeqs()', computes pairwise distances with 'DECIPHER::DistanceMatrix()', converts distances to match scores ('p_match = 1 - distance'), and joins taxonomy metadata. The resulting data frame is the input to 'train_likelihood_model()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with one row per reference sequence. Must contain: 'composite_id' Unique sequence identifier (character). 'sequence' DNA string (character, IUPAC alphabet accepted). rank columns One column per rank in 'rank_system' (e.g., 'genus', 'species'). |
| rank_system | no | NULL | Character vector of rank names *coarse to fine* (e.g., 'c("family", "genus", "species")'). Default 'NULL' auto-detects from columns in 'reference_df'. |
| max_dist | no | 0.25 | Numeric (default '0.25'). Pairs with distance above this threshold are dropped to save memory. Roughly, 0.25 ~= 75% identity. The 75% identity threshold is a standard floor for retaining distantly related taxa in barcode reference databases. |
| min_seq_len | no | 100L | Integer (default '100'). Sequences shorter than this are discarded before alignment. Ignored if 'barcode_term' is supplied and this argument is left at its default - see 'barcode_term' below. |
| max_seq_len | no | 2000L | Integer (default '2000'). Sequences longer than this are discarded before alignment. Ignored if 'barcode_term' is supplied and this argument is left at its default - see 'barcode_term' below. |
| filter_unnamed | no | TRUE | Logical (default 'TRUE'). If 'TRUE', sequences whose finest-rank taxonomy column (the last element of 'rank_system', typically 'species') is blank ('""') or 'NA' are removed before alignment. Blank names produce spurious within-species pairs - two unidentified sequences both labelled '""' are classified as conspecific even though they may represent entirely different taxa. In a broad 18S reference database this can account for the majority of apparent within-species pairs. Set to 'FALSE' only if blank finest-rank values are intentional. |
| max_seqs_per_taxon | no | NULL | Integer or 'NULL' (default 'NULL'). If supplied, at most this many sequences are retained per finest-rank taxon before alignment, chosen by random sampling using the current RNG state (set 'set.seed()' before calling for reproducibility). This prevents heavily-sequenced model organisms or domestic species from dominating the within-species distribution and thereby distorting model training. For typical vertebrate barcode databases a value of '10L'-'20L' is sufficient; the resulting within-species pair counts per taxon are at most 'max_seqs_per_taxon * (max_seqs_per_taxon - 1) / 2'. 'NULL' disables the cap (current behaviour). |
| barcode_term | no | NULL | Character or 'NULL' (default 'NULL'). When supplied AND 'min_seq_len'/'max_seq_len' are both left at their defaults, resolves the length window via 'TaxaTools::resolve_barcode_lengths(barcode_term)' instead of using the generic [100, 2000] default. Explicit 'min_seq_len'/'max_seq_len' always override this, matching 'resolve_barcode_lengths()''s own override convention. This exists because the generic default length window does NOT guarantee every retained sequence covers the same amplicon window - only that it is a plausible barcode-length fragment of _some_ kind. A broad NCBI free-text search (e.g. 'barcode_term = "12S"' at fetch time) can return sequences describing a genomically different stretch of the same gene (older primer sets, broader mitochondrial fragments) that still happen to pass a length filter - silently mixing two different genomic windows into what looks like one self-consistent H1/H2 training set (the documented "Paralabrax footgun": a real 0% MiFish-primer-site hit rate on sequences that had already passed the generic length filter). Passing a _specific, registered primer variant_ here (e.g. '"MiFishU"', not just '"12S"') gives the strongest guarantee, since that resolves to the literature-verified real PCR amplicon length rather than a broader per-gene range; a bare marker name (e.g. '"12S"') only guarantees "roughly the right marker," not amplicon-window comparability, and does not by itself close this gap. See 'diagnostics/sebastes_chromis_confirmation.R' for the case this was found in and the (now-superseded, use this parameter instead) manual pre-filter pattern it used. verbose: Logical (default 'TRUE'). Passed straight through to 'DECIPHER::AlignSeqs()'/'DECIPHER::DistanceMatrix()''s own native progress reporting (percent-complete, ETA) - this function used to hardcode both to 'FALSE', silencing DECIPHER's own display for the two steps that dominate wall time on a large reference set (alignment cost grows worse than linearly in sequence count, so a large reference database can run for hours with no visible signal of progress). This function's OWN 'message()' calls (length-filter counts, rank-system auto-detection, timing summaries) are unaffected either way - only DECIPHER's own in-progress display is controlled by this parameter. 'FALSE' restores the old fully-silent behavior (e.g. for a non-interactive/logged batch run where a live progress bar is meaningless). |
| verbose | no | TRUE |  |
| by_genus | no | FALSE | Logical (default 'FALSE'; see @section Per-genus alignment below). 'TRUE' replaces the single whole-set 'DECIPHER::AlignSeqs()' call with many small per-genus alignments (each augmented with up to 'max_foreign_reps_per_genus' other genera's chosen representatives) plus one small cross-genus-representative alignment - same output shape, much better scaling on a reference set with many genera. Requires '"genus"' in 'rank_system' (errors if absent); a sequence with a blank/NA 'genus' value is dropped with a message rather than aborting the run (a real broad fetch legitimately has some genus-unresolved accessions - e.g. environmental samples). |
| max_foreign_reps_per_genus | no | 20L | Integer or 'NULL' (default '20L'). Only relevant when 'by_genus = TRUE' - caps how many OTHER genera's representative sequences get added to each genus's own augmented alignment (see @section Per-genus alignment below). 'NULL' means no cap (every other genus's representative is added, regardless of how many genera exist) - real-data validation found this costs MORE than whole-set alignment, and gets worse as genus count grows (a real 221-genus reference set took ~40 minutes uncapped vs ~10 minutes for whole-set), since the added cost scales with the SQUARE of genus count. A finite cap keeps the added cost linear in genus count instead (genera x cap, not genera x (genera - 1)) - each genus draws an INDEPENDENT random subset of 'cap' other genera's representatives (not one subset shared across every genus, which would starve whichever genera never happen to fall inside it), so coverage stays roughly even across genera even though it is no longer exhaustive. '0L' disables the augmentation entirely (equivalent to the original representative-only design this fixes - see the @section below for why that understates 'gap_logit'). |

**Value:** A data frame with one row per sequence pair within 'max_dist': 'id_x', 'id_y' 'composite_id' values for each pair member. 'p_match' Match score (1 - distance), range (0, 1]. 'coverage' Alignment coverage: number of positions where both sequences contribute a non-gap character, divided by the shorter unaligned sequence length. Range (0, 1]. Values near 1.0 indicate nearly complete overlap; values n

### calibrate_query_noise(model_params, match_df, priors, plausibility_threshold = 0.001, min_confident_obs = 30L, offset_form = c("linear", "constant"), min_calib_species = 8L, calibrate_sigma = FALSE, evidence_col = NULL, logit_epsilon = 1e-04, verbose = TRUE)

Calibrate a trained likelihood model to real query-vs-reference behavior

'train_likelihood_model()' estimates H1 (known-species) parameters entirely from reference-vs-reference pairs - two clean, curated database sequences compared to each other. That process cannot see technical noise specific to real queries (PCR error, sequencing error, degradation, ASV-inference artifacts), so a real, correctly-identified query routinely scores lower than the trained H1 mean predicts, and the "unreferenced" hypotheses (whose means sit further down the score axis, exactly where real queries land) can end up out-competing the correct referenced species.

| Param | Required | Default | Doc |
|---|---|---|---|
| model_params | yes |  | Object of class '"taxa_model_params"' from 'train_likelihood_model()'. |
| match_df | yes |  | Data frame. Canonical match object for the _same_ dataset 'model_params' was trained for (e.g. 'match_obj_restored'). Must contain 'observation_id', 'genus', and a score column. priors: Data frame. Occurrence-based priors for the same dataset (e.g. 'TaxaExpect' output), with 'taxon_name', 'taxon_name_rank', and 'theta_mean'. |
| priors | yes |  |  |
| plausibility_threshold | no | 0.001 | Numeric (default '1e-3'). Passed to 'identify_confident_observations()'. |
| min_confident_obs | no | 30L | Integer (default '30L'). Minimum number of confident observations required to compute an offset. Below this, the function warns and returns 'model_params' unchanged (offset = 0, sigma ratio = 1). |
| offset_form | no | c("linear", "constant") | Character (default '"linear"'). '"linear"' remaps each H1 mean through a robustly-fit line 'intercept + slope * trained_mean' (fit on per-species medians) - a level-aware calibration that estimates, rather than assumes, how much per-species reference-scale structure transfers to the inference scale, and reduces to a pure additive offset when it fully transfers (slope = 1). It is the default because, across every real dataset tested (external-pipeline- and BLAST-scored DNA markers), the fitted slope collapsed toward 0 and a single calibrated location fit real query scores as well as or better than per-species-mean-plus-offset (see "Level-aware recalibration"). '"constant"' is the conservative opt-out - one additive offset applied to every H1 mean (the package's original behavior), appropriate when you would rather retain per-species locations than collapse them on a location-only validation set. '"linear"' falls back to '"constant"' (with a warning) when fewer than 'min_calib_species' confident species, or no spread of trained means, are available - so a thin-reference marker (e.g. one with only a handful of referenced species) is handled safely without a caller having to special-case it. In particular, when the trained per-species score means have no spread at all - which happens whenever 'train_likelihood_model()' reports 'Stats$tau2_score = 0' under 'shrinkage = "empirical_bayes"' (observed on every production site to date, per that shrinkage mode's own documentation) - every species' H1 mean IS the global mean by construction, '"linear"' has no spread of trained means to fit against, and it falls back to '"constant"' with a warning - so requesting '"linear"' there is moot. |
| min_calib_species | no | 8L | Integer (default '8L'). Minimum number of distinct confident species (spanning a range of trained means) required to fit the 'offset_form = "linear"' line. Ignored when 'offset_form = "constant"'. |
| calibrate_sigma | no | FALSE | Logical (default 'FALSE'). Also apply the MAD-based variance-scale correction described in the Sigma correction section below. *Empirically made results worse on the one real dataset this was tested against* - read that section before enabling. |
| evidence_col | no | NULL | Character or 'NULL' (default 'NULL'). Name of a column in 'match_df' giving each observation's raw evidence quantity (e.g. DNA read depth, image detection count, acoustic recording duration). When supplied, the median of this quantity across the confident observations is stored as 'reference_evidence' in the returned $Query_Calibration slot - the baseline 'evaluate_likelihoods()'(evidence_col=) divides a query's own evidence quantity by, at inference time, to scale H1 sigma per-observation (more evidence than this baseline tightens sigma, less widens it - unlike the rejected flat 'calibrate_sigma' correction above, this is validated per-observation, not as one population-wide constant; see 'TaxaLikely/CLAUDE.md' for the within-species correlation this is based on). Median chosen for the same robustness reason as the mean offset (a real, right-skewed depth distribution can span 5+ orders of magnitude). A *global* median across the whole confident set, not per-species/genus - per-observation evidence quantity already carries the relevant signal regardless of species, and normalizing away a species' typical evidence level would reintroduce the same population-mismatch problem that broke the flat sigma correction. Calibration (this function, needs bulk confident-observation data) and inference ('evaluate_likelihoods()', works on any number of observations, including one) are deliberately decoupled: once 'reference_evidence' is baked into 'model_params' here, scoring a single new observation later needs no recalibration. When 'NULL' (default) or too few confident observations exist, 'reference_evidence' is left 'NA' - 'evaluate_likelihoods()' then applies no evidence-based adjustment at all, rather than guessing a baseline from insufficient data. |
| logit_epsilon | no | 1e-04 | Logit clipping value (default '1e-4'), matching 'evaluate_likelihoods()''s own default. verbose: Logical (default 'TRUE'). Print the estimated offset and how many confident observations/genera it was based on. |
| verbose | no | TRUE |  |

**Value:** 'model_params', with 'H1_Global_Mu["score_logit"]' and 'H1_Lookup$mu_score' shifted by the estimated offset; 'H1_Sigma["score_logit", "score_logit"]' and every 'H1_Lookup$sigma_score' scaled by the estimated variance ratio (unless 'calibrate_sigma = FALSE'); and a new $Query_Calibration slot recording 'offset_logit', 'offset_form' (the form actually applied, which may be '"constant"' after a '"lin

### check_cross_genus_sampling_noise(reference_df, rank_system = NULL, max_dist = 0.25, min_seq_len = 100L, max_seq_len = 2000L, filter_unnamed = TRUE, max_seqs_per_taxon = NULL, barcode_term = NULL, max_foreign_reps_per_genus = 20L, n_replicates = 5L)

How Much Does the Random Cross-Genus Draw Move the Estimate?

'build_sequence_matrix(by_genus = TRUE)' represents each genus by ONE randomly-drawn sequence when building the cross-genus sample that feeds H3 (and H2's pooled fallback). This re-runs that whole draw-and-align step 'n_replicates' times and reports how much the resulting cross-genus pair distribution moves across replicates - a transparency report, like 'TaxaExpect::kernel_budget_sensitivity()''s own per-group budget table, not a pass/fail gate. There is no universal "good enough" spread to check against; the point is to make the spread visible so you can judge whether it is small relative to

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  |  |
| rank_system | no | NULL |  |
| max_dist | no | 0.25 |  |
| min_seq_len | no | 100L |  |
| max_seq_len | no | 2000L |  |
| filter_unnamed | no | TRUE |  |
| max_seqs_per_taxon | no | NULL |  |
| barcode_term | no | NULL |  |
| max_foreign_reps_per_genus | no | 20L |  |
| n_replicates | no | 5L | Integer (default '5L'). How many independent random representative draws to compare. Each draw consumes the caller's RNG state ('sample()', same convention as 'max_seqs_per_taxon') - do NOT call 'set.seed()' between replicates, or every "replicate" would be identical. |

**Value:** A list: 'replicates' Data frame, one row per replicate: 'replicate', 'n_cross_genus_pairs', 'mean_p_match', 'median_p_match', 'sd_p_match'. 'summary' Named list: the range (min, max) and coefficient of variation (sd/mean) of 'mean_p_match' across replicates - the single number worth looking at first.

### compute_rank_thresholds(seq_matrix, rank_system = NULL, prior_weight = 10, threshold_grid = seq(0, 100, by = 1))

Derive marker-specific rank_thresholds via per-rank Youden's J

A real, exported, marker-agnostic version of 'diagnostics/score_floor_roc_sweep.R''s per-rank Youden's J logic: given a 'build_sequence_matrix()'-style pairwise distance matrix for YOUR marker and reference database, returns the percent-identity threshold at each taxonomic rank (species/genus/family) that maximizes true-positive minus false-positive rate for that rank's own, correctly-matched positive/ negative classes - species tier: TP = within-species, FP = congeneric; genus tier: TP = same-genus, FP = confamilial; family tier: TP = same-family, FP = cross-family. Reuses the identical genus

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_matrix | yes |  | Data frame of pairwise match scores, as returned by 'build_sequence_matrix()', for the SAME marker/reference database 'score_consensus()' will be scoring against. Every pair must have known taxonomy on both sides (species/genus/family), which is exactly what 'build_sequence_matrix()' already produces. |
| rank_system | no | NULL | Character vector of rank names, coarse to fine, e.g. 'c("family", "genus", "species")'. Default 'NULL' auto-detects from '.x'-suffixed columns in 'seq_matrix' (same convention as 'train_likelihood_model()'). |
| prior_weight | no | 10 | Numeric. Empirical Bayes shrinkage weight for the per-genus/per-family curves (default '10.0', matching 'train_likelihood_model()''s own default). |
| threshold_grid | no | seq(0, 100, by = 1) | Numeric vector of percent-identity thresholds to search over. Default 'seq(0, 100, by = 1)'. |

**Value:** A named numeric vector, a subset of 'c(species=, genus=, family=)' depending on what 'rank_system'/'seq_matrix' make computable - directly usable as 'TaxaAssign::score_consensus(rank_thresholds = ...)'. Errors if nothing is computable at all (fewer than 2 usable rank levels).

### correct_training_bias(scored_df, count_col, score_col = "score_original", tau = 0)

Correct classifier scores for training-database representation bias

Discriminative classifiers (iNaturalist CV, BirdNET) trained by standard cross-entropy estimate a Bayes posterior: their raw output for species i is proportional to L(obs \mid species_i) \times n_i, where L(obs \mid species_i) is the true visual/acoustic likelihood and n_i is the number of training examples for species i. Raw classifier scores therefore favor well-represented (common, well- photographed/recorded) taxa over rare ones with equal true evidential support. This function divides out an estimate of that training-count bias so that scores across candidates are on a more comparable sca

| Param | Required | Default | Doc |
|---|---|---|---|
| scored_df | yes |  | Data frame of raw classifier output, one row per candidate species per observation. Must contain 'score_col'. |
| count_col | yes |  | Character scalar. Name of the column holding each candidate's training-database representation count (e.g. '"n_observations"' for iNaturalist CV output, '"n_recordings"' for BirdNET/Xeno-canto output after joining 'audit_acoustic_coverage(xc_recordings = TRUE)''s census onto 'scored_df' by taxon). If absent from 'scored_df', a warning is issued and every row falls through unchanged (equivalent to all counts being 'NA'). |
| score_col | no | "score_original" | Character scalar (default '"score_original"', matching 'assign_scores()''s default 'score_col'). Name of the raw score column to correct. tau: Non-negative numeric scalar (default '0', changed from '1.0' in Session 151 - see "Default changed" in Details). Global exponent applied to every candidate's count (see Details) - 'tau = 0' disables correction entirely (returns scores unchanged); 'tau = 1' is the theoretically Fisher-consistent full correction; values above 1 apply stronger-than-theoretical correction (Menon et al.'s own tuned optimum on one benchmark was 2.6). Every real calibration run against this function's own real classifier output so far (image, and acoustic on a properly powered re-test) found tau ~= 0 optimal - raise it only after calibrating against real labeled data for your own data type (see Details). |
| tau | no | 0 |  |

**Value:** 'scored_df' with 'score_col' overwritten by the corrected score, plus three added columns: 'score_uncorrected' (pre-correction value), 'n_used' (count applied per row, 'NA' where unavailable), and 'tau_used' (exponent actually applied per row).

### detect_suppressed_candidates(match_obj, score_col = "score_original", observation_id_col = "observation_id", perfect_threshold = 100, purity_threshold = 0.99, singleton_threshold = 0.98)

Detect pipeline rules that suppress candidate rows in a match object

Inspects a match object for evidence that an upstream tool suppressed lower-scoring candidates. Three patterns are recognised:

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. Standardised match object containing at least 'observation_id_col'. 'score_col' is optional; Rules 1 and 2 are skipped when it is absent. |
| score_col | no | "score_original" | Character. Name of the score column (default '"score_original"'). |
| observation_id_col | no | "observation_id" | Character. Name of the observation ID column (default '"observation_id"'). |
| perfect_threshold | no | 100 | Numeric. Score at or above which a candidate is considered a "perfect" match for Rule 1 detection (default '100'). Set to 95 for pipelines that enforce a 95-percent identity floor, for example. |
| purity_threshold | no | 0.99 | Numeric in (0, 1]. Fraction of qualifying observations that must exhibit the pattern for the rule to be flagged (default '0.99'). A high value reduces false positives from rounding artefacts. |
| singleton_threshold | no | 0.98 | Numeric in (0, 1]. Fraction of all observations that must be singletons (1 row) for Rule 3 to be flagged (default '0.98'). |

**Value:** A named list: 'rule_detected' Logical. 'TRUE' if any rule is flagged. 'rules' Character vector of flagged rule names (may be empty). 'perfect_only' Logical. 'max_score_ties' Logical. 'best_only' Logical. 'has_score_col' Logical. Whether 'score_col' was found. 'n_total' Integer. Unique observations. 'n_perfect_obs' Integer. Observations with >=1 score >= 'perfect_threshold'. 'purity_perfect' Numeri

### evaluate_likelihoods(match_df, model_params, rank_system = NULL, ratio_threshold = 0.01, min_match_threshold = 0.5, alpha = 0.001, n_sims = 0L, score_bounds = NULL, logit_epsilon = 1e-04, max_gap_ceiling = NULL, min_coverage = NULL, evidence_col = NULL, evidence_max_ratio = 1, verbose = FALSE)

Convert match scores to likelihoods for all queries

Applies the trained likelihood model to every 'observation_id' in the match object and returns a tidy data frame suitable for input to 'TaxaAssign::compute_posterior()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame in the canonical match-object format (output of 'TaxaMatch::standardize_match_data()' or user-supplied). Must contain 'observation_id', 'score_original' (or 'p_match'; legacy 'score' also accepted), 'taxon_name', 'taxon_name_rank', and taxonomy columns matching 'rank_system'. |
| model_params | yes |  | Object of class '"taxa_model_params"' from 'train_likelihood_model()'. The scale H1/H2/H3 were trained on ('model_params$Score_Transform', '"logit"' or '"sqrt_mismatch"') is read automatically - callers do not supply or track it separately. 'evidence_col'/'min_coverage' work identically regardless of 'Score_Transform': their SE(transform(score)) propto 1/sqrt(N) justification holds (with a different, 'p'-dependent proportionality constant) for either scale, confirmed via the delta method. |
| rank_system | no | NULL | Character vector of rank names *coarse to fine* (e.g., 'c("family", "genus", "species")'). Default 'NULL' auto-detects from columns in 'match_df'. |
| ratio_threshold | no | 0.01 | Minimum likelihood ratio to retain a hypothesis (default '0.01'). Hypotheses with likelihood ratio less than 1% of the best hypothesis are dropped. This removes noise hypotheses that would not meaningfully affect posterior probabilities. Note: the per-species sigma floor (see Details) ensures that well-sampled species with artificially tight training distributions still clear this threshold at realistic query scores, so the default '0.01' is appropriate for most eDNA workflows. |
| min_match_threshold | no | 0.5 | Minimum raw score to consider a candidate (default '0.50'). Queries whose best candidate scores below 50% identity are considered unmatchable and routed to the $unresolved output for re-evaluation with a coarser 'rank_system'. alpha: Mahalanobis p-value cutoff for outlier rejection (default '0.001'). See '.evaluate_one_query()' for full description. n_sims: Monte Carlo simulations per query (default '0' = point estimate only). |
| alpha | no | 0.001 |  |
| n_sims | no | 0L |  |
| score_bounds | no | NULL | Optional 'c(min, max)' for score normalization. |
| logit_epsilon | no | 1e-04 | Logit clipping value (default '1e-4'). |
| max_gap_ceiling | no | NULL | Gap cap (default '5.0'). Caps gap at 5 logit units (roughly the gap between 99.3% and 50% identity) to prevent extreme outliers from dominating model estimates. |
| min_coverage | no | NULL | Numeric or 'NULL' (default 'NULL'). When not 'NULL' and the match object contains a 'coverage' column (e.g., BLAST 'qcovs' divided by 100, or bounding-box area from 'TaxaMatch::read_animl_output(bbox_cols=)'), candidate rows below this threshold are dropped *before* per-taxon score aggregation. A 'coverage' column can be added to any match object via the 'coverage_col' parameter of 'TaxaMatch::standardize_match_data()'. Typical values: '0.8' (80\ 'NA' coverage values are always retained (treated as fully covered). When 'coverage' is absent from 'match_df', this parameter is silently ignored. *Every candidate below threshold (fixed 2026-09-09):* when 'min_coverage' drops EVERY candidate row for a given 'observation_id', that observation is routed to $unresolved (with a named warning) instead of erroring - the same degrade-gracefully convention already used for the coarser-than-'rank_system' case above. Confirmed to hit 195/800 (24.4\ comparison at a Youden's-J-calibrated 'min_coverage'; before this fix, any such observation crashed the whole call with '"replacement has 1 row, data has 0"'. Re-run 'evaluate_likelihoods()' on $unresolved with a lower (or 'NULL') 'min_coverage' to resolve these queries. |
| evidence_col | no | NULL | Character or 'NULL' (default 'NULL'). Name of a column in 'match_df' giving each candidate's raw evidence quantity (e.g. DNA read depth, image detection count, acoustic recording duration - whatever is appropriate for the data type). When supplied, 'H1' sigma is rescaled by a factor '1/sqrt(evidence_ratio)', where 'evidence_ratio' is this quantity divided by 'model_params$Query_Calibration$reference_evidence' - a baseline set once, in bulk, by 'calibrate_query_noise()'(evidence_col=). Unlike 'min_coverage'/coverage inflation above, this is symmetric: an observation with _more_ evidence than the baseline tightens sigma, not just widens it for less. The rescale is only ever *applied* when doing so is provably non-decreasing for the density at the query's own (pre-rescale) standardized distance from the species mean - see @section Evidence-based sigma rescaling below for the exact criterion and why it replaced an earlier unconditional version. Produces 'score_likelihood_evidence', a parallel point-estimate column (no Monte Carlo variant, matching 'score_likelihood_cov''s own precedent) - identical to 'score_likelihood' when 'evidence_col' is absent, not present in a given candidate row, the model was never calibrated with a 'reference_evidence' baseline, or the gate criterion below isn't met; never guessed. Works identically for a single-observation 'match_df' as for a large batch, since the baseline is read from 'model_params', not re-derived from 'match_df' itself. |
| evidence_max_ratio | no | 1 | Numeric (default '1'). Caps how much 'evidence_ratio' may _tighten_ sigma (values above this are clipped to it before the '1/sqrt()' scaling); widening for 'evidence_ratio < 1' is never capped. Default '1' means evidence never tightens sigma at all, only widens - found necessary empirically: an uncapped ratio crashed a real, correctly-identified, high-depth observation's 'H1' likelihood to exactly 0 (its score wasn't precisely at the trained mean, and real variability doesn't vanish just because evidence is abundant). Raise above '1' only after validating on your own data - the gate described in @section Evidence-based sigma rescaling protects the tightening direction using the same criterion as widening, but has not itself been validated against real over-tightening cases the way the widen-only default has been. verbose: Logical (default 'FALSE'). When 'TRUE', prints a message each time a species falls back to global parameters (no species-specific lookup entry found). |
| verbose | no | FALSE |  |

**Value:** A named list with two components: $likelihoods Data frame with one row per 'observation_id' x taxon hypothesis, suitable for input to 'TaxaAssign::compute_posterior()': 'observation_id', 'taxon_name', 'taxon_name_rank', 'hypothesis_type' ('"specific_candidate"', '"unreferenced_species"', or '"unreferenced_genus"'), 'raw_likelihood', 'raw_likelihood_cov', 'raw_likelihood_evidence' (the bivariate-no

### expand_unreferenced_hypotheses(likelihood_df, unreferenced_df)

Expand unreferenced hypotheses from genus/family level to named species

Moved here from TaxaAssign (Session 150) - this is the value-modeling half of unreferenced-taxon handling ("borrow a likelihood from referenced relatives"), which belongs next to 'unreferenced_candidates()' (the candidate-generation half) rather than in the posterior-computation package. It still requires both a TaxaLikely likelihood object and a TaxaExpect-derived unreferenced-species list, so it must still run after both are available and before 'TaxaAssign::compute_posterior()' - that is a workflow-ordering requirement, not a package-dependency one, since this function only ever consumes pl

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_df | yes |  | Data frame - the $likelihoods component returned by 'evaluate_likelihoods()'. Must contain 'observation_id', 'taxon_name', 'taxon_name_rank', 'hypothesis_type', 'score_likelihood', 'score_likelihood_mean', 'score_likelihood_sd'. |
| unreferenced_df | yes |  | Data frame of unreferenced but plausible species. Must contain columns 'species' (binomial name), 'genus', and 'family'. Built from TaxaExpect rows confirmed as unreferenced by 'audit_barcode_coverage()'. May optionally contain an 'observation_id' column (Session 159): a row with 'NA' (or when the column is absent entirely) applies to every observation sharing its genus/family, the original global-list behavior; a row with a real 'observation_id' applies only to that one observation. This lets a caller inject a species that IS globally referenced (so it would never appear via 'audit_barcode_coverage()') but lacks reference evidence covering one specific query's region - see 'restore_suppressed_candidates()''s 'check_regional_overlap' mechanism, whose rejected congeners are returned in exactly this shape via 'attr(result, "regional_unreferenced")'. |

**Value:** 'likelihood_df' with generic '"unreferenced_species"' and '"unreferenced_genus"' rows replaced by named species rows where matches are found. Column set is unchanged; new rows carry 'NA' for most extra columns in the input (e.g. 'constraint_applied', which is genuinely row-specific), except 'score_likelihood_cov', 'score_likelihood_evidence', and 'h2_delta_source' when present - these, like 'score

### fetch_bold_reference_sequences(taxa, barcode_term = NULL, rank_system = c("family", "genus", "species"), max_per_species = NULL, include_location = TRUE)

Fetch reference sequences from BOLD Systems for model building

Searches BOLD's v5 Data Portal API by taxon name and returns a 'reference_df' ready for 'build_sequence_matrix()' - the BOLD analog of 'fetch_ncbi_reference_sequences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxa | yes |  | Character vector of taxon names to search. Each is resolved and queried separately; results are combined and de-duplicated by 'processid'. |
| barcode_term | no | NULL | Character vector of BOLD marker codes to keep (e.g. '"COI-5P"'), matched against the returned 'marker_code' column. 'NULL' (default) keeps every marker returned. |
| rank_system | no | c("family", "genus", "species") | Character vector of taxonomy ranks, coarse to fine (default 'c("family", "genus", "species")'). Resolved from BOLD's own taxonomy columns ('kingdom', 'phylum', 'class', 'order', 'family', 'subfamily', 'genus', 'species', 'subspecies' - confirmed live, Session 136). |
| max_per_species | no | NULL | Integer or 'NULL' (default 'NULL'). Maximum sequences per species (stratified downsampling), matching 'fetch_ncbi_reference_sequences()''s convention. Requires '"species"' to be in 'rank_system'. |
| include_location | no | TRUE | Logical (default 'TRUE'). Keep the 'lat'/'lon'/'country' columns parsed from BOLD's own 'coord'/'country/ocean' fields. 'NA' where BOLD has no collection-location metadata (common - most BOLD records are GenBank-mined and carry no field-collection coordinates). |

**Value:** A data frame ('reference_df') with columns: 'composite_id' BOLD 'processid'. 'sequence' DNA sequence string (BOLD's 'nuc' field). rank columns One column per rank in 'rank_system'. 'lat', 'lon', 'country' Only when 'include_location = TRUE'. Ready for input to 'build_sequence_matrix()'.

### fetch_ncbi_reference_sequences(taxa, barcode_term, rank_system = c("family", "genus", "species"), min_len = NULL, max_len = NULL, max_per_species = NULL, max_per_genus = NULL, priority_taxa = NULL, max_sequences = 10000L, min_per_taxon = 50L, blacklist_regex = paste0("uncultured|environmental|predicted|", "vector|synthetic|unverified"), min_date = NULL, max_date = NULL, cache_dir = tools::R_user_dir("TaxaLikely", "cache"), ncbi_api_key = NULL, include_location = FALSE, keep_out_of_range = FALSE, max_out_of_range_per_species = 2L, max_out_of_range_len = 200000L, count_attempts = 3L, on_count_failure = c("warn", "error"), evict_unreachable_cache = TRUE)

Fetch reference sequences from NCBI for model building

Renamed from 'fetch_reference_sequences()' (Session 136) now that a second live-API reference source ('fetch_bold_reference_sequences()', BOLD Systems) exists - the old name didn't say NCBI anywhere, which stopped being safe once a second source existed. The deprecated 'fetch_reference_sequences()' forwarding alias was removed entirely in a later session (no real callers remained; see NAME_CHANGE_HISTORY.md).

| Param | Required | Default | Doc |
|---|---|---|---|
| taxa | yes |  | Character vector of taxon names to search. Can be any rank: species, genus, family, order, or class (e.g., '"Fundulus"', '"Gobiidae"', '"Actinopterygii"'). Each taxon is searched separately; results are combined. |
| barcode_term | yes |  | Character scalar or vector of marker names (e.g., '"12S"', 'c("COI", "Co1", "Coxi")'). Multiple synonyms are OR-ed in the NCBI query. |
| rank_system | no | c("family", "genus", "species") | Character vector of taxonomy ranks, *coarse to fine* (e.g., 'c("family", "genus", "species")'). These ranks are resolved from the NCBI taxonomy database. min_len: Integer or NULL. Minimum sequence length (bp). If NULL, auto-resolved from 'barcode_term' using built-in defaults. max_len: Integer or NULL. Maximum sequence length (bp). If NULL, auto-resolved from 'barcode_term'. Set both to NULL and supply wide manual values to cast a broader net (useful for exploring how sequence length relates to errors). |
| min_len | no | NULL |  |
| max_len | no | NULL |  |
| max_per_species | no | NULL | Integer or NULL (default NULL). Maximum sequences to retain per species (stratified downsampling). NULL disables species-level capping. |
| max_per_genus | no | NULL | Integer or NULL (default NULL). Maximum sequences per genus after species-level capping. NULL disables genus-level capping. |
| priority_taxa | no | NULL | Character vector or NULL (default NULL). Species names that should be fully represented in the reference. Typically the species from the user's match data. When total NCBI hits exceed 'max_sequences', priority species are searched individually and given full allocation; the remaining budget is split proportionally across the broader 'taxa' (families/genera). This ensures the model has good within-species and between-species distances for species that actually appear in the query data. |
| max_sequences | no | 10000L | Integer (default 10000). Safety valve for total download volume. If the total NCBI hit count exceeds this, sequences are subsampled proportionally across taxa (each taxon gets at least 'min_per_taxon' sequences). Priority taxa (if provided) are fetched first; the remaining budget is allocated to broader family searches. |
| min_per_taxon | no | 50L | Integer (default 50). When subsampling due to 'max_sequences', each taxon is guaranteed at least this many sequences (or all of them if fewer exist). |
| blacklist_regex | no | paste0("uncultured\|environmental\|predicted\|", "vector\|synthetic\|unverified") | Character scalar. Regex pattern for filtering sequence titles. Sequences whose title matches this pattern are excluded. |
| min_date | no | NULL | Character or NULL (default; e.g. pass '"2010/01/01"' to set one). Earliest publication date for sequences. 'NULL' means no lower bound - internally resolved to the sentinel '"1900/01/01"' (predates GenBank's own founding), not left off the query entirely, so it composes safely with a supplied 'max_date' alone. |
| max_date | no | NULL | Character or NULL (default; e.g. pass '"2024/12/31"' to set one). Latest publication date. 'NULL' means no upper bound - internally resolved to the sentinel '"3000/12/31"', matching 'min_date''s NULL handling above. |
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Character path. Per-taxon intermediate results are cached here, enabling resumable downloads when NCBI rate-limits or the session is interrupted. Default 'tempdir()' (clears on R restart). Set to a persistent path for cross-session caching, or 'NULL' to disable. |
| ncbi_api_key | no | NULL | Character or NULL. NCBI API key (increases rate limit from 3 to 10 requests/second). Can also be set via the 'ENTREZ_KEY' environment variable. |
| include_location | no | FALSE | Logical (default 'FALSE'). When 'TRUE', fetches each accession's full GenBank record (a real, separate NCBI round trip - not free) and adds 'lat'/'lon'/'country' columns parsed from the 'source' feature's 'lat_lon'/'country' qualifiers. 'NA' where the record has no collection-location metadata (common for older/predicted sequences). Neither '.fetch_summaries_batched()' (ESummary) nor '.fetch_taxonomy_map()' (taxonomy DB) - the two record types this function otherwise fetches - carry these qualifiers, so this is a genuinely separate fetch, not a free re-parse of existing output. |
| keep_out_of_range | no | FALSE | Logical (default 'FALSE'). When 'TRUE', sequences outside [eff_min_len, eff_max_len] (e.g. complete mitogenomes) are kept - tagged via the new 'in_barcode_range' output column - instead of being dropped, capped separately per species by 'max_out_of_range_per_species' so they never compete with in-range sequences for the 'max_per_species'/'max_per_genus' training-set budget. Default 'FALSE' preserves this function's original behavior exactly. Exists so a caller needing to check whether a species has ANY real sequence overlapping a specific genomic region (not just whether it has some barcode-length reference) can do so locally against 'reference_df', without a separate on-demand NCBI fetch - see 'restore_suppressed_candidates()''s regional-overlap check. |
| max_out_of_range_per_species | no | 2L | Integer (default '2L'). Cap on out-of-range sequences retained per species when 'keep_out_of_range = TRUE'. Ignored otherwise. |
| max_out_of_range_len | no | 200000L | Integer (default '200000L'). Upper bound on how large a sequence can be to still be retained under 'keep_out_of_range = TRUE'. Without this, a well-sequenced species' whole-genome scaffold (a real case found in production use: 111 million bp, not a mitogenome) would be retained just as readily as a real ~15-20kb mitogenome, making any later alignment against it pathologically slow for no benefit - a scaffold that large was never a candidate for "the rescuable barcode region is embedded in this over-length submission" the way a mitogenome or chloroplast genome is. The default comfortably covers any real animal mitogenome or plant chloroplast genome (~120-160kb) with margin, while excluding genome/ scaffold-scale sequences by orders of magnitude. Ignored when 'keep_out_of_range = FALSE'. |
| count_attempts | no | 3L | Integer (default '3L'). How many times to try each per-taxon NCBI count query before giving up on it. A count query can fail transiently, typically NCBI throttling, which 'rentrez' often surfaces as the unhelpful message '"subscript out of bounds"'. Retries use exponential backoff on top of the usual inter-request delay. |
| on_count_failure | no | c("warn", "error") | One of '"warn"' (default) or '"error"'. What to do when a taxon's count query still fails after 'count_attempts' tries. *This is not a cosmetic condition.* A failed count is excluded from the sequence budget, which sets that taxon's fetch cap to zero, so the taxon contributes NO reference sequences at all and any species-level call within it later rests on no reference data of its own. Observed for real on the 2026-09-14 PtConception 12S run: 7 taxa failed (the first 7 queried, after which every remaining query succeeded), silently costing 352 species-level consensus rows their own reference data, including _Medialuna californiensis_, _Zalophus californianus_ and _Tursiops truncatus_. Re-issuing the identical queries afterwards succeeded for all 7, confirming the failures were transient. '"warn"' keeps the run alive but reports the affected taxa by name in one consolidated warning and message, because the original per-taxon warnings went unnoticed in a 17,000-line log. Use '"error"' for an unattended production run where a silently degraded reference database is worse than a failed run. |
| evict_unreachable_cache | no | TRUE | Logical (default 'TRUE'). When a taxon's cache file is WRITTEN, also delete that same taxon's cache files whose names the current key cannot produce for any arguments - superseded generations left behind by an earlier key widening. This is the only part of this function that deletes anything, and it is deliberately narrow: the test is a proof, not a heuristic (see '.ref_cache_grammar()'), it is scoped to the one taxon just rewritten, it never touches a file over 5 MB, and it says what it removed. Two files that differ only in a key VALUE - different length bounds, a different 'rank_system' - are different queries, not generations, and are never touched. Set 'FALSE' to keep every historical generation. The whole-store equivalent is 'taxalikely_evict_unreachable_cache()', which reports rather than deletes unless asked. |

**Value:** A data frame ('reference_df'), carrying a 'count_failures' attribute (always present, possibly zero-length) naming any taxa dropped because their count query failed - check it with 'attr(reference_df, "count_failures")' rather than reading the log. Columns: 'composite_id' NCBI accession (version suffix stripped). 'sequence' DNA sequence string. rank columns One column per rank in 'rank_system' (e.

### fetch_xc_recording_locations(species_names, verbose = TRUE)

Fetch per-recording locations from Xeno-canto for one or more species

Thin looping wrapper around '.xc_recording_locations()' - same 1-second-per-species rate limit 'audit_acoustic_coverage' already uses for its own Xeno-canto queries. Unlike 'audit_acoustic_coverage(xc_recordings = TRUE)', which only keeps a per-species recording _count_, this returns the per-recording 'lat'/'lon' the Xeno-canto v3 API already provides in the same response body.

| Param | Required | Default | Doc |
|---|---|---|---|
| species_names | yes |  | Character vector of binomial species names (e.g. '"Turdus migratorius"'). verbose: Logical. Print progress messages. Default 'TRUE'. |
| verbose | no | TRUE |  |

**Value:** A data frame with one row per recording, across all requested species: 'species', 'xc_id' (Xeno-canto's own catalog number), 'lat', 'lon', 'country'.

### filter_top_hypotheses(likelihood_df, rank_system = NULL)

Keep only the finest-rank specific candidates per query

After 'evaluate_likelihoods()', each query may have specific candidates at multiple ranks (e.g., both species- and genus-level hits). This function retains only the finest-rank specific candidates - coarser candidates are redundant when a finer-rank hit exists - while keeping all '"unreferenced_species"' and '"unreferenced_genus"' rows.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_df | yes |  | Data frame - the $likelihoods component of the list returned by 'evaluate_likelihoods()'. |
| rank_system | no | NULL | Character vector of rank names *coarse to fine*. Used to assign numeric rank scores for comparison. Default 'NULL' auto-detects from the 'taxon_name_rank' values in 'likelihood_df'. |

**Value:** Filtered version of 'likelihood_df'.

### identify_confident_observations(match_df, priors, plausibility_threshold = 0.001)

Identify confident, non-circular observations for query-noise calibration

Finds genera where exactly one species clears a local occurrence-plausibility threshold in 'priors' (e.g. 'TaxaExpect' output), then returns the best-scoring row per 'observation_id' for every 'match_df' observation whose genus is one of those. Because the single-plausible-species call comes from independent occurrence/range data - not from 'match_df''s own scores or the likelihood model being calibrated - these observations can be treated as (very likely) correct species identifications without circularity.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Canonical match object (e.g. 'match_obj_restored') with 'observation_id', 'genus', and a score column ('score_original', 'score', or 'p_match', checked in that order). priors: Data frame. Occurrence-based priors (e.g. 'TaxaExpect' output) with 'taxon_name', 'taxon_name_rank', and 'theta_mean'. |
| priors | yes |  |  |
| plausibility_threshold | no | 0.001 | Numeric (default '1e-3'). Minimum 'theta_mean' for a species to count as "locally plausible" in a genus. Values are typically well-separated from background/floor priors (often ~1e-6); the default is a conservative gap above that floor. |

**Value:** Data frame: one row per confident 'observation_id', with all 'match_df' columns plus 'confident_genus' (the genus that qualified) and 'confident_species' (its single plausible species, from 'priors').

### infer_exclude_predicted(match_obj, accession_col = NULL, verbose = TRUE)

Infer whether predicted sequences were excluded from the BLAST reference

Examines accession numbers in a match object to determine whether the BLAST reference database included computationally predicted sequences (NCBI 'XR_' and 'XM_' RefSeq accessions). Returns 'TRUE' if predicted sequences appear to have been excluded - the correct value for 'audit_barcode_coverage''s 'exclude_predicted' argument when using curated databases (Jonah Ventures, SILVA, PR2, MIDORI). Returns 'FALSE' if predicted sequences are present, or 'NA' when the accession column contains only custom (non-NCBI) identifiers and the inference cannot be made.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. A standardised match object as produced by 'TaxaMatch::standardize_match_data()' or a compatible user-supplied table. Must contain an accession column. |
| accession_col | no | NULL | Character scalar or 'NULL'. Name of the accession column. If 'NULL' (default) the function auto-detects a column named '"accession"', '"Accession"', '"acc"', or '"accno"'. verbose: Logical. If 'TRUE' (default), emits a message explaining the inference and its basis. |
| verbose | no | TRUE |  |

**Value:** A single logical: 'TRUE' (exclude predicted - no 'XR_'/'XM_' accessions found among NCBI-format accessions), 'FALSE' (do not exclude - predicted accessions are present in the match object), or 'NA' (cannot determine - no standard NCBI accessions found; set 'exclude_predicted' explicitly).

### interpret_model(model_params, print_report = TRUE)

Summarise a trained likelihood model

Converts the internal logit-space parameters of a '"taxa_model_params"' object back to interpretable percentages and prints a formatted report. Returns the summary tables invisibly for programmatic access.

| Param | Required | Default | Doc |
|---|---|---|---|
| model_params | yes |  | Object of class '"taxa_model_params"' returned by 'train_likelihood_model()'. |
| print_report | no | TRUE | Logical (default 'TRUE'). If 'FALSE', suppresses console output. |

**Value:** An invisible named list with elements: 'hypothesis_baselines' Data frame: expected match % and expected gap % for H1, H2, H3. The gap is the difference between the best match and the runner-up. H2/H3 have gap near 0 because when the true species or genus is absent, no candidate has a clear advantage. 'global_h1' Data frame: global mean score, gap, and SD. 'hierarchy' Data frame: per-rank counts an

### read_crabs_output(crabs_file, rank_system = NULL, max_n_bases = NULL, require_species = TRUE, dereplicate = FALSE)

Read a CRABS-formatted reference database

Reads the internal output format produced by CRABS (Creating Reference databases for Amplicon-Based Sequencing; Jeunen et al. 2023), a widely-used eDNA reference database builder. CRABS outputs a single tab-delimited file with no header row and 11 fixed columns, with missing ranks represented as the literal string '"NA"'.

| Param | Required | Default | Doc |
|---|---|---|---|
| crabs_file | yes |  | Character scalar. Path to the CRABS internal-format file. |
| rank_system | no | NULL | Character vector of ranks to include, *coarse to fine* (e.g., 'c("family", "genus", "species")'). Must be a subset of the seven CRABS taxonomy columns: 'kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species'. Default 'NULL' auto-detects from the file: all columns that have at least one non-'NA' value are included. For likelihood model training, 'c("family", "genus", "species")' is typically sufficient. |
| max_n_bases | no | NULL | Integer or 'NULL' (default 'NULL'). Drop sequences longer than this many bases. Useful for removing chimeric or incorrectly-assembled entries that CRABS length filters may have missed. 'NULL' retains all lengths. |
| require_species | no | TRUE | Logical (default 'TRUE'). When 'TRUE', rows with a missing or invalid species name are dropped. Validity is checked by 'TaxaTools::is_plausible_binomial()', which rejects 'sp.', 'cf.', 'aff.', and 'uncultured' names. Set to 'FALSE' to retain genus-level-only references. |
| dereplicate | no | FALSE | Logical (default 'FALSE'). When 'TRUE', exact-duplicate sequences within the same species are collapsed to one representative (first accession retained). CRABS itself offers primer- trimmed dereplication; this option works on the raw sequence column and is a complement, not a replacement. |

**Value:** A data frame ('reference_df') with columns: 'composite_id' Accession string (version suffix stripped). rank columns One column per rank in 'rank_system'. 'sequence' DNA sequence string. Ready for input to 'build_sequence_matrix()'.

### read_reference_fasta(fasta_path, taxonomy = NULL, rank_system, taxonomy_file = NULL)

Read a local FASTA file into a reference data frame

Reads a FASTA file and joins it to a user-supplied taxonomy table to produce a 'reference_df' suitable for 'build_sequence_matrix()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| fasta_path | yes |  | Character scalar. Path to a FASTA file ('.fasta', '.fa', '.fna'). |
| taxonomy | no | NULL | Data frame with a 'composite_id' column and one column per rank in your rank system. 'composite_id' values must match the accessions parsed from FASTA headers. Supply either 'taxonomy' or 'taxonomy_file', not both. |
| rank_system | yes |  | Character vector of rank names, *coarse to fine* (e.g., 'c("family", "genus", "species")'). Used to validate that all rank columns are present in 'taxonomy', or to determine which ranks to extract from 'taxonomy_file'. |
| taxonomy_file | no | NULL | Character scalar or 'NULL' (default). Path to a 2-column taxonomy TSV file (see section above). Supply either 'taxonomy_file' or 'taxonomy', not both. Requires 'rank_system' to be specified explicitly. |

**Value:** A data frame ('reference_df') with columns 'composite_id', 'sequence', and one column per rank. Ready for input to 'build_sequence_matrix()'.

### report_likelihood(model, verbose = FALSE)

Generate a Report Section for Likelihood Estimation

Summarizes a trained likelihood model into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| model | yes |  | A 'taxa_model_params' object from 'train_likelihood_model'. verbose: Logical. Print summary messages. Default 'FALSE'. |
| verbose | no | FALSE |  |

**Value:** A 'report_section' object with: methods Template text describing the likelihood model. results Template text summarizing model diagnostics. params Named list of model parameters. statistics Named list of model diagnostics.

### restore_suppressed_candidates(match_obj, reference_df, rank_system = NULL, score_col = "score_original", observation_id_col = "observation_id", delta = 0.5, max_per_obs = 10L, model_params = NULL, alpha = 0.001, max_dist = 0.25, check_regional_overlap = FALSE, seq_matrix = NULL, min_regional_coverage = 0.5, accession_col = "accession", sequence_col = NULL, candidate_species_filter = NULL, taxaexpect_priors = NULL, grid_id_col = "grid_id", taxon_col = "taxon_name", grid_col = "grid_id", theta_col = "theta_mean", budget_ratio_cap = 19, max_level4_per_anchor = 10L, verbose = TRUE)

Restore candidates suppressed by upstream pipeline rules

Reframed design (see the TaxaID monorepo's own 'ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md' design document for the full history - development-repository context, not shipped with the installed package): the function's job is not "restore candidates so more of them can individually win" but to detect whether the anchor's apparent win is real or an artifact of upstream suppression, so that downstream consensus logic can back off from a false-precision specific-species call when it isn't. Every same-genus congener in 'reference_df' not already present for an observation is che

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. Standardised match object. |
| reference_df | yes |  | Data frame. Reference database (output of 'fetch_ncbi_reference_sequences()', 'read_reference_fasta()', or 'read_crabs_output()'). Must contain the same genus/species columns as 'match_obj'. |
| rank_system | no | NULL | Character vector or 'NULL'. Rank columns coarse-to-fine (e.g. 'c("family","genus","species")'). Auto-detected when 'NULL'. |
| score_col | no | "score_original" | Character. Score column name (default '"score_original"'). |
| observation_id_col | no | "observation_id" | Character. Observation ID column name (default '"observation_id"'). delta: Numeric. Only used by the no-score pathway (see '@details') - score gap between H1's synthetic '1.0' and a restored row's synthetic score (default '0.5', on the 0-100 scale; used as 'delta / 100' against the '1.0' baseline). Has no effect when 'match_obj' carries real scores - restored rows there get a real, hierarchy-resolved score instead ('@section Score-sourcing hierarchy'). |
| delta | no | 0.5 |  |
| max_per_obs | no | 10L | Integer. Maximum restored candidates per observation (default '10L'), applied to the final admitted set (after Purpose A/B gating), not to the raw congener list. |
| model_params | no | NULL | A 'taxa_model_params' object (output of 'train_likelihood_model()') or 'NULL' (default). Used two ways: (1) Purpose A's outlier test needs the anchor species' own sigma ('H1_Lookup', floored at 'H1_Sigma[1,1]', matching 'evaluate_likelihoods()''s own convention) - Purpose A never admits any candidate when this is 'NULL'; (2) Level 3 of the score-sourcing hierarchy prefers 'H2_Lookup$delta_shrunk' (the model's own genus-specific congener-divergence estimate) over a raw seq_matrix median when available, keeping a restored row's imputed score consistent with the same estimate 'evaluate_likelihoods()' already uses for that genus's H2 rows. alpha: Numeric (default '0.001'). Purpose A's outlier-test p-value cutoff - identical parameter and identical test to 'evaluate_likelihoods()''s own 'alpha', reused rather than inventing a second calibrated constant for the same question. |
| alpha | no | 0.001 |  |
| max_dist | no | 0.25 | Numeric (default '0.25'). Purpose B's admission floor, on the same distance ('1 - p_match') scale as 'build_sequence_matrix()''s own 'max_dist' - reuse the same value passed there for consistency. |
| check_regional_overlap | no | FALSE | Logical (default 'FALSE'). When 'TRUE', enables the score-sourcing hierarchy's Level 4 (live Tier 2 pairwise alignment, '@section Score-sourcing hierarchy') for candidates that Levels 1-3 can't resolve for free - without it, such candidates simply get no score and are never restored. Requires 'accession_col' in 'match_obj' and 'composite_id'/ 'sequence' in 'reference_df' (errors if absent). This also doubles as Purpose A's regional-overlap guarantee for real, without a second position check: any candidate resolved via Levels 1-3 is position-safe by construction ('seq_matrix' only ever contains properly-sized, in-window sequences), so the regional-overlap concern only ever bites exactly where Level 4 already lives. |
| seq_matrix | no | NULL | Data frame or 'NULL'. Output of 'build_sequence_matrix()' (needs 'id_x'/'id_y'/'p_match'/ 'coverage'), the source for Levels 1-3 of the score-sourcing hierarchy and Level 4's Tier 1 lookup. Restoration is a no-op for the scored pathway when this is 'NULL' and 'check_regional_overlap = FALSE' - there is no free evidence to source a score from and no live alignment enabled either. |
| min_regional_coverage | no | 0.5 | Numeric in (0, 1]. Minimum alignment coverage required for Level 4's live Tier 2 alignment to accept a congener as overlapping (default '0.5'). Only used when 'check_regional_overlap = TRUE'. |
| accession_col | no | "accession" | Character. Column in 'match_obj' naming each row's own reference accession (default '"accession"'). |
| sequence_col | no | NULL | Character or 'NULL' (default 'NULL'). Column in 'match_obj' carrying each observation's own raw query DNA sequence, enabling Level 4's Tier 2b fallback (see '@section Score-sourcing hierarchy') for match objects with no live BLAST alignment coordinates at all. 'NULL' means only Tier 1/2a run. |
| candidate_species_filter | no | NULL | Character vector or 'NULL' (default 'NULL'). Two roles, both cost- or plausibility-related, never a correctness gate on the free hierarchy levels: (1) defines Purpose B's plausible-candidate set; (2) *is Level 4's own default cost gate* ('@section Level 4 cost control', revised 2026-07-18) - a candidate not on this list only reaches the expensive live-alignment step if 'taxaexpect_priors'' ratio test says it's specifically worth it. Never gates Levels 1-3 - Purpose A's free-tier genus-wide sweep sees every congener regardless of this filter (the design spec's red flag 1 stays closed: a plausibility filter can no longer make an observation get zero signal, it can only skip the expensive step for an implausible congener). Intended to hold whatever locally-plausible- species list a caller would apply downstream anyway (e.g. TaxaExpect occurrence priors' 'taxon_name' column). Species names must match 'reference_df''s own 'species_col' values exactly (full binomial, e.g. '"Fundulus parvipinnis"'). 'NULL' (default) means every same-genus congener is both Purpose-B-eligible AND Level-4-eligible - no narrowing at all, matching the original pre-redesign behavior at some real cost (see '@section Level 4 cost control' for two real, measured cases). |
| taxaexpect_priors | no | NULL | Data frame or 'NULL' (default 'NULL'). A plain data frame - this package has no dependency on TaxaExpect and never calls into it; the name and default 'taxon_col'/ 'grid_col'/'theta_col' column names are simply chosen to match 'TaxaExpect::estimate_kernel_priors()''s own '$priors' output shape (the current recommended path - the archived 'generate_full_priors()' used the identical column names), so that object can be passed directly without renaming columns. Any data frame with the right columns (or with 'taxon_col'/'grid_col'/ 'theta_col' overridden to match your own column names) works. Powers the floor-vs-documented ratio fallback in '@section Level 4 cost control' for a candidate NOT on 'candidate_species_filter'. 'NULL' (default) means that fallback is unavailable - a candidate missing the filter is never worth Level 4 regardless of its real occurrence support. |
| grid_id_col | no | "grid_id" | Character. Column in 'match_obj' naming each observation's own grid cell (default '"grid_id"'), looked up against 'taxaexpect_priors'' grid column. Only used when 'taxaexpect_priors' is supplied. |
| taxon_col | no | "taxon_name" | Character. Column names within 'taxaexpect_priors' for the species/grid/prior-mean columns (defaults '"taxon_name"', '"grid_id"', '"theta_mean"'). |
| grid_col | no | "grid_id" | Character. Column names within 'taxaexpect_priors' for the species/grid/prior-mean columns (defaults '"taxon_name"', '"grid_id"', '"theta_mean"'). |
| theta_col | no | "theta_mean" | Character. Column names within 'taxaexpect_priors' for the species/grid/prior-mean columns (defaults '"taxon_name"', '"grid_id"', '"theta_mean"'). |
| budget_ratio_cap | no | 19 | Numeric (default '19'). Derived, not an arbitrary tuning knob: from 'posterior_consensus()''s 'min_posterior' default of '0.05' and a same-or-worse-than- anchor likelihood bound ('@section Level 4 cost control'). |
| max_level4_per_anchor | no | 10L | Numeric (default '10L', use 'Inf' to disable). Hard backstop cap on how many distinct candidates get a live Level 4 alignment attempt per anchor accession, independent of 'candidate_species_filter'/'taxaexpect_priors' - insurance against a large or absent filter (or a permissive ratio) still forcing an unbounded number of expensive alignments for one anchor. See '@section Level 4 cost control'. verbose: Logical. Emit summary messages (default 'TRUE'). |
| verbose | no | TRUE |  |

**Value:** 'match_obj' with restored '"suppressed_candidate"' rows appended (or unchanged if nothing qualified), plus new 'is_restored', 'restoration_basis', 'restoration_level', and 'restoration_source_accession' columns. 'restoration_level' (added 2026-08-08) is the '.resolve_hierarchy_score()' level (1-4) that produced a restored row's score, 'NA' for original (non- restored) rows and for the no-score pat

### subset_local_database(fasta_path, taxa, rank, rank_system = c("family", "genus", "species"), taxonomy_file = NULL, taxonomy = NULL, max_n_bases = NULL, require_species = FALSE)

Subset a Large Local Reference Database by Taxon

Filters a large local FASTA + taxonomy file to a user-supplied taxon list, returning a 'reference_df' ready for 'build_sequence_matrix()' or 'train_likelihood_model()'. The taxonomy file is parsed first to identify matching sequence IDs; the FASTA is then streamed record-by-record, keeping only those IDs. Peak memory scales with the number of matching sequences, not the total database size, making this suitable for multi-gigabyte databases such as SILVA SSU, MIDORI2, or Greengenes2.

| Param | Required | Default | Doc |
|---|---|---|---|
| fasta_path | yes |  | Character. Path to the FASTA file. Plain text and '.gz'-compressed files are both supported. taxa: Character vector. Taxon names to retain (e.g., 'c("Fundulidae", "Gobiidae")' for family-level filtering, or 'c("Fundulus", "Gambusia")' for genus-level). rank: Character scalar. The rank at which 'taxa' are defined; must be one of the values in 'rank_system' (e.g., '"genus"', '"family"'). |
| taxa | yes |  |  |
| rank | yes |  |  |
| rank_system | no | c("family", "genus", "species") | Character vector, coarse to fine (default 'c("family", "genus", "species")'). Must include 'rank'. |
| taxonomy_file | no | NULL | Character or 'NULL'. Path to a 2-column taxonomy TSV (sequence ID TAB taxonomy string) in QIIME2/RESCRIPt, SILVA, MIDORI2, or GTDB format. Prefix-style ('k__', 'd__') and positional semicolon formats are both auto-detected. Exactly one of 'taxonomy_file' or 'taxonomy' must be supplied. |
| taxonomy | no | NULL | Data frame or 'NULL'. Pre-parsed taxonomy with a 'composite_id' column plus one column per rank in 'rank_system'. Exactly one of 'taxonomy' or 'taxonomy_file' must be supplied. |
| max_n_bases | no | NULL | Integer or 'NULL'. Drop sequences longer than this many bases after extraction (useful for removing genomic contaminants from amplicon databases). |
| require_species | no | FALSE | Logical (default 'FALSE'). If 'TRUE', drop sequences with 'NA' in the 'species' column. Requires '"species"' to be in 'rank_system'. |

**Value:** A 'reference_df': a data frame with columns 'composite_id', plus one column per rank in 'rank_system', plus 'sequence'. Ready for 'build_sequence_matrix()' or 'write_reference_fasta()'.

### suggest_unreferenced_species(match_df, context = NULL, barcode_term = "COI", llm_fn = NULL, data_type = "eDNA", reference_species = NULL, expand_to_family = FALSE, max_date = NULL, min_len = NULL, max_len = NULL, taxa_per_call = 30L, pause_seconds = 1, ncbi_api_key = NULL, verbose = FALSE)

Suggest Unreferenced Species Using an LLM

A fast, LLM-first alternative to 'audit_barcode_coverage()' for unreferenced species detection. An *unreferenced species* is a described taxon that shares a genus (or family, with 'expand_to_family = TRUE') with a scored reference match candidate but is absent from the reference dataset. The definition of "absent" depends on 'data_type': no NCBI barcode sequence (eDNA), or not in the model's training species list (acoustic / image).

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Canonical match object from TaxaMatch (or equivalent). Required column: 'taxon_name'. Optional but strongly recommended: 'genus' (if absent, derived from 'taxon_name'). Required for 'expand_to_family = TRUE': 'family'. context: Optional named list or single-row data frame with location / habitat context for the LLM. Recognised fields: 'ecoregion', 'lat', 'lon', 'date', 'habitat'. NULL (default) sends no context. |
| context | no | NULL |  |
| barcode_term | no | "COI" | Character scalar or vector. One or more marker search terms (e.g. '"12S"', 'c("12S", "MiFish")'). Multiple terms are OR-ed. Default '"COI"'. llm_fn: Function or NULL. Provider function following the TaxaTools 'llm_fn' pattern: accepts a single character string prompt and returns a single character string response. Default NULL resolves to 'getOption("TaxaID.llm_fn")' when set, otherwise 'TaxaTools::call_api' (requires TaxaTools). |
| llm_fn | no | NULL |  |
| data_type | no | "eDNA" | Character. One of '"eDNA"' (default), '"acoustic"', or '"image"'. Controls how "unreferenced" is defined: • '"eDNA"': unreferenced = no NCBI barcode sequence for the target marker. Uses NCBI nucleotide count queries. • '"acoustic"': unreferenced = absent from the acoustic model training set (e.g., not in BirdNET's species list). Requires 'reference_species'. • '"image"': unreferenced = absent from the image classifier training set. Requires 'reference_species'. |
| reference_species | no | NULL | Character vector or NULL. Required when 'data_type' is '"acoustic"' or '"image"'. The known-species list for the acoustic or image model (e.g., the BirdNET species list). Species absent from this vector are classified as unreferenced. Ignored when 'data_type = "eDNA"'. Default NULL. |
| expand_to_family | no | FALSE | Logical. If 'TRUE', genera for which the LLM returned zero plausible species trigger a second LLM call asking for plausible species in OTHER genera of the same family. These *family-level unreferenced species* fill the role of TaxaLikely's H3 (unreferenced genus) hypothesis with named species. Requires a 'family' column in 'match_df'. Default 'FALSE'. |
| max_date | no | NULL | Optional character scalar. Restricts unreferenced species detection to sequences present in NCBI on or before this date. Format: '"YYYY"', '"YYYY/MM"', or '"YYYY/MM/DD"'. NULL uses the current state of GenBank. min_len: Integer or NULL. Minimum sequence length ('SLEN' filter). NULL uses a barcode-specific default. max_len: Integer or NULL. Maximum sequence length. NULL uses the barcode-specific default. |
| min_len | no | NULL |  |
| max_len | no | NULL |  |
| taxa_per_call | no | 30L | Integer >= 1. Maximum genera per LLM call. Default 30. |
| pause_seconds | no | 1 | Numeric. Seconds to pause between LLM calls. Default 1. |
| ncbi_api_key | no | NULL | Optional NCBI API key. Raises rate limit from 3 to 10 requests per second. Can also be set via the 'ENTREZ_KEY' environment variable. verbose: Logical. If 'TRUE', prints each prompt and raw LLM response. Default 'FALSE'. |
| verbose | no | FALSE |  |

**Value:** A character vector of unreferenced species names with class 'c("unreferenced_species_result", "character")'. 'length()' returns the total number of unreferenced species (congener + family-level combined). Pass directly to 'TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)'.

### taxalikely_clear_cache(cache_dir = tools::R_user_dir("TaxaLikely", "cache"), older_than_days = NULL, dry_run = FALSE)

Report and clear TaxaLikely's on-disk cache

'fetch_ncbi_reference_sequences()' caches one small file per (taxon, barcode_term, length window, date range, out-of-range settings, rank_system) combination it has ever been asked for, plus one file per accession under 'fasta/'; 'audit_barcode_coverage()' caches one checkpoint per (rank, marker, params) combination it has run. All cache under a persistent, user-level directory and none expires automatically. This function reports how much space the cache is using and, unless 'dry_run = TRUE', removes it.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Character. Cache directory to inspect/clear. Defaults to 'tools::R_user_dir("TaxaLikely", "cache")', the same default used by 'fetch_ncbi_reference_sequences()'/'audit_barcode_coverage()'. |
| older_than_days | no | NULL | Numeric or 'NULL'. When supplied, only files older than this many days (by modification time) are targeted. 'NULL' (default) targets every recognized cache file in 'cache_dir'. dry_run: Logical. If 'TRUE', reports what would be removed without removing anything. Default 'FALSE'. |
| dry_run | no | FALSE |  |

**Value:** Invisibly, a data frame of the targeted files ('path', 'size_mb', 'mtime'), possibly zero rows.

### taxalikely_evict_unreachable_cache(cache_dir = tools::R_user_dir("TaxaLikely", "cache"), dry_run = TRUE, max_file_mb = 5)

Delete only the reference-cache files no call can ever hit again

The cache key for 'fetch_ncbi_reference_sequences()' has been widened four times, each time to fix a real staleness crash: 'barcode_term', 'rank_system', 'keep_out_of_range', and the length and date bounds. Every one of those fixes was correct, and every one silently ORPHANED the entire preceding generation rather than replacing it - content-keyed caching without eviction does not replace a cache when the key changes, it doubles it. On the development machine that came to 1,584 of 3,517 meta files (45%).

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Character. Cache directory to inspect. Defaults to 'tools::R_user_dir("TaxaLikely", "cache")', the same default used by 'fetch_ncbi_reference_sequences()'. dry_run: Logical. If 'TRUE' (the DEFAULT, unlike the sibling clear functions), reports what would be removed without removing it. |
| dry_run | no | TRUE |  |
| max_file_mb | no | 5 | Numeric. Files larger than this are reported and left in place even when 'dry_run = FALSE', per the 2026-09-14 policy decision to auto-evict small metadata '.rds' files but to report-and-confirm before deleting anything large. A meta file is about 1 KB, so this is a structural guard rather than an active filter. 'NULL' disables it. |

**Value:** Invisibly, a data frame of the targeted files ('path', 'size_mb', 'mtime'), possibly zero rows.

### train_likelihood_model(raw_df, rank_system = NULL, score_bounds = NULL, min_observed_sigma = NULL, prior_weight = 10, use_hierarchy = TRUE, anchor_perfect = TRUE, logit_epsilon = 1e-04, max_gap_ceiling = NULL, score_transform = "logit", min_pair_coverage = 0.8, shrinkage = c("empirical_bayes", "fixed"))

Train the hierarchical likelihood model on reference-vs-reference scores

Fits an Empirical Bayes model using pairwise within-species match scores (from 'build_sequence_matrix()') to learn species-specific score distributions. Per-species parameters are shrunk toward a global mean, with shrinkage strength inversely proportional to the number of observations for that species. Optionally uses 'lme4' random intercepts per taxonomic rank for more robust estimation.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_df | yes |  | Data frame of pairwise match scores, as returned by 'build_sequence_matrix()'. Passed through '.prep_training_data()'. |
| rank_system | no | NULL | Character vector of rank names, *coarse to fine* (e.g., 'c("family", "genus", "species")'). Default 'NULL' auto-detects from the '.x'-suffixed columns in 'raw_df'. |
| score_bounds | no | NULL | Optional 'c(min, max)' for score normalization. |
| min_observed_sigma | no | NULL | Numeric or 'NULL' (default). Floor on observed within-species score variance. Prevents overfitting on species with very low variance (e.g., a species with two nearly identical reference sequences). 'NULL' resolves to '1.0' for 'score_transform = "logit"' (in logit space, 1.0 corresponds to meaningful within-species variation) or the equivalent rescaled value for '"sqrt_mismatch"' - see 'score_transform' below. |
| prior_weight | no | 10 | Numeric. Equivalent pseudo-sample size for Empirical Bayes shrinkage toward the global mean. Controls how strongly species-specific estimates are regularized. A value of 10 means each species estimate is pulled toward the global mean as if 10 additional observations at the global mean had been added. Higher values produce more conservative (less species-specific) estimates; lower values trust per-species data more but risk overfitting for species with few references. Default '10.0'. |
| use_hierarchy | no | TRUE | Logical (default 'TRUE'). If 'TRUE' and 'lme4' is available, fits random intercepts per rank level to stabilize estimates across the taxonomic hierarchy. |
| anchor_perfect | no | TRUE | Logical (default 'TRUE'). If 'TRUE', injects synthetic perfect-match observations into the H1 training data to prevent the perfection penalty (see section below). |
| logit_epsilon | no | 1e-04 | Numeric. Logit-clipping value (default '1e-4'). Used only when 'score_transform = "logit"'. |
| max_gap_ceiling | no | NULL | Numeric or 'NULL' (default). Gap cap. 'NULL' resolves to '5.0' for 'score_transform = "logit"' (roughly the gap between 99.3% and 50% identity, in logit units) or '0.6234' for '"sqrt_mismatch"' (the same 99.3%-vs-50% reference gap on that scale) - prevents extreme outliers from dominating model estimates either way. |
| score_transform | no | "logit" | Character, '"logit"' (default) or '"sqrt_mismatch"'. The scale H1/H2/H3 are all modeled on - must be shared across all three hypotheses, since they are compared via density ratios at the same observed point (a valid likelihood ratio requires one consistent scale; mixing transforms across hypotheses would need an explicit change-of-variables correction that this package does not implement). '"logit"' ('log(p/(1-p))') is the package's original scale. '"sqrt_mismatch"' ('-sqrt(1-p)') was added in Session 158 after real 12S congener data showed '"logit"' gives a genuinely backwards answer for one of the package's more novel claims: whether a genus's species are hard to tell apart (small, consistent divergence) or easy to tell apart (larger, more variable divergence). On the raw match-proportion scale, tight genera show lower congener-score variance, as expected - but under '"logit"', this can reverse sign, because nearly all real barcode matches sit close to 100% identity, exactly where logit's derivative diverges fastest. '"sqrt_mismatch"' treats divergence as a rare-event count (few mismatches out of many aligned bases - the regime real data is actually in), for which square-root is the classical variance-stabilizing transform; it recovers the correct qualitative ordering where '"logit"' does not. See 'evaluate_likelihoods()''s own documentation and [[project_job2_unreferenced_relatives]] in the TaxaID memory system for the full empirical derivation, including why several other standard transforms (probit, complementary log-log) were checked and rejected. '"sqrt_mismatch"' is bounded to [-1, 0] rather than unbounded like '"logit"' - a Gaussian fit to it is technically an approximation for that reason, but a mild one in practice, since real observations concentrate near 0 (good matches), far from the -1 boundary. *Not yet ported to this scale*: 'calibrate_query_noise()' and 'evaluate_likelihoods()''s 'evidence_col'/'min_coverage' mechanisms all assume '"logit"' internally and will error rather than silently produce wrong numbers if combined with a '"sqrt_mismatch"'-trained model. |
| min_pair_coverage | no | 0.8 | Numeric in (0, 1] or 'NULL' (default '0.8'). The alignment-coverage floor a reference-vs-reference pair must meet before it may DEFINE a reference's best foreign match, best congener match, or best conspecific match ('coverage' column from 'build_sequence_matrix()'). Must equal the coverage floor the match object was built under - 'TaxaMatch::blast_sequences(min_query_coverage = 80)' is '0.8' here - so that training and inference see the same pair population; 'evaluate_likelihoods()''s check against the match object is one-directional - it warns only when the match object admits LOWER coverage than this model's own floor (a 0.01 tolerance), never the other way around. This is NOT a data filter: no pair is removed from the data and no species is ever dropped (a reference with no qualifying conspecific pair falls back to its best one). 'NULL' disables the floor; a 'raw_df' without a 'coverage' column skips it with a message. See the "Alignment-coverage floor" section. |
| shrinkage | no | c("empirical_bayes", "fixed") | '"empirical_bayes"' (default) or '"fixed"'. How each species' H1 mean score and mean gap are shrunk toward the global mean. '"fixed"' is the original 'N / (N + prior_weight)' weight. '"empirical_bayes"' estimates the real between-species variance of the means ('tau^2', method of moments, per dimension) and weights each species by 'tau^2 / (tau^2 + sigma^2 / N)': no signal beyond noise collapses every species to the global mean, real signal lets well-referenced species keep more of their own. The estimate is reported in 'Stats$tau2_score'/'Stats$tau2_gap' and the per-species weights in 'H1_Lookup$shrink_w_score'/'shrink_w_gap'. Variance shrinkage always uses the fixed weight. Needs at least 3 species; otherwise falls back to '"fixed"' with a message. |

**Value:** A named list (class '"taxa_model_params"') with slots: 'H1_Lookup' Data frame with per-species parameters: 'lookup_key', 'rank', 'mu_score', 'mu_gap', 'sigma_score', 'n_obs_species' (number of within-species reference sequences trained on - used by 'evaluate_likelihoods()' to weight the Monte Carlo uncertainty of the trained mean; see that function's own documentation). 'H1_Global_Mu' Named numeri

### trim_to_amplicon(reference_df, primer_fwd = NULL, primer_rev = NULL, barcode_term = NULL, min_len = NULL, max_len = NULL, max_mismatch_rate = 0.15, verbose = TRUE)

Extract the amplicon region from over-length reference sequences (in-silico PCR)

GenBank mixes short, purpose-cut barcode submissions with much longer sequences (full mitochondrial genomes, whole-genome scaffolds, full ribosomal operons) that happen to contain the target locus somewhere inside them. 'build_sequence_matrix()''s 'min_seq_len'/'max_seq_len' filter excludes these outright - correct for well-sampled species, but for a poorly-sampled species whose only GenBank record is over-length, exclusion throws away the only genuine reference data available for it.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with at least 'composite_id' and 'sequence' columns (the same object produced by 'fetch_ncbi_reference_sequences()' / 'read_reference_fasta()' and consumed by 'build_sequence_matrix()'). |
| primer_fwd | no | NULL | Character scalars: forward and reverse primer sequences, 5' to 3', IUPAC-degenerate bases allowed. Supply both, or neither (to look up 'barcode_term' in TaxaTools::barcode_primer_defaults instead). |
| primer_rev | no | NULL | Character scalars: forward and reverse primer sequences, 5' to 3', IUPAC-degenerate bases allowed. Supply both, or neither (to look up 'barcode_term' in TaxaTools::barcode_primer_defaults instead). |
| barcode_term | no | NULL | Character scalar naming a registered primer set (e.g. '"MiFishU"'), resolved via 'TaxaTools::resolve_barcode_primers()'. Also used to auto-resolve 'min_len'/'max_len' via 'TaxaTools::resolve_barcode_lengths()' when those are not supplied directly. |
| min_len | no | NULL | Integer. Governs which sequences are left untouched as already barcode-length (<= max_len) versus checked for the amplicon region. Default 'NULL' auto-resolves both from 'barcode_term' via 'TaxaTools::resolve_barcode_lengths()' - in that case, the FINAL plausibility check on a matched amplicon span instead uses a bound derived from the registered primer pair's own 'amplicon_range' (the literature-reported variable-region length) plus each primer's length, since 'min_len'/'max_len' alone describe a general marker-length window, not a primer-inclusive matched span (a real, fixed 2026-08-10 bug: the old behavior rejected every genuine MiFish-U hit as "implausible" by ~11bp - see this package's own Known Footguns entry). If you supply 'min_len'/'max_len' explicitly, that choice is used as-is for BOTH the over-length decision and the final plausibility check, unchanged from prior behavior. |
| max_len | no | NULL | Integer. Governs which sequences are left untouched as already barcode-length (<= max_len) versus checked for the amplicon region. Default 'NULL' auto-resolves both from 'barcode_term' via 'TaxaTools::resolve_barcode_lengths()' - in that case, the FINAL plausibility check on a matched amplicon span instead uses a bound derived from the registered primer pair's own 'amplicon_range' (the literature-reported variable-region length) plus each primer's length, since 'min_len'/'max_len' alone describe a general marker-length window, not a primer-inclusive matched span (a real, fixed 2026-08-10 bug: the old behavior rejected every genuine MiFish-U hit as "implausible" by ~11bp - see this package's own Known Footguns entry). If you supply 'min_len'/'max_len' explicitly, that choice is used as-is for BOTH the over-length decision and the final plausibility check, unchanged from prior behavior. |
| max_mismatch_rate | no | 0.15 | Numeric in [0, 1) (default '0.15'). Maximum fraction of primer positions allowed to mismatch the sequence at the binding site (rounded down to an integer count of bases per primer). Accounts for real SNP variation at primer-binding sites; degenerate IUPAC bases in the primer itself are handled separately and do not count as mismatches when compatible with the sequence base. verbose: Logical (default 'TRUE'). Print progress/summary messages. |
| verbose | no | TRUE |  |

**Value:** 'reference_df' with 'sequence' updated in place for successfully trimmed rows, plus two new columns: 'amplicon_trimmed' Logical. 'TRUE' if this row's sequence was replaced with an extracted amplicon. 'amplicon_trim_note' Character. One of '"within_length_range_no_trim_needed"', '"extracted_via_primer_match_sense_strand"', '"extracted_via_primer_match_antisense_strand"', '"primers_not_found_or_impl

### unreferenced_candidates(match_df, rank_system = NULL, include_unreferenced_family = FALSE)

Add unreferenced taxon placeholder rows to a match object

Given a canonical match object (one row per 'observation_id' x reference accession), adds placeholder rows for taxon hypotheses absent from the reference database:

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Canonical match object from 'TaxaMatch::standardize_match_data()' or equivalent. Must contain 'observation_id', 'taxon_name', and 'taxon_name_rank'. Taxonomy columns matching 'rank_system' (e.g., 'family', 'genus', 'species') are used to derive H2/H3 taxon names. A 'score_original' column is optional; when present it identifies the best anchor candidate. |
| rank_system | no | NULL | Character vector of rank names *coarse to fine* (e.g., 'c("family", "genus", "species")'). When 'NULL' (default), auto-detected from column names using 'TaxaTools::extended_ranks'. At least two ranks are required. |
| include_unreferenced_family | no | FALSE | Logical (default 'FALSE'). When 'TRUE', one '"unreferenced_family"' catch-all row is added per observation with all taxonomy columns set to 'NA'. Use when running 'assign_scores()' without TaxaExpect priors (e.g., the LLM shortcut pathway) to absorb posterior mass from taxa outside all represented families. Do *not* set to 'TRUE' when using TaxaExpect priors - the prior distribution already covers unrepresented families. |

**Value:** A data frame with the same columns as 'match_df', plus 'hypothesis_type' ('"specific_candidate"' for original rows; '"unreferenced_species"', '"unreferenced_genus"', or '"unreferenced_family"' for added rows). Added rows have 'score_original = NA' (and any other score columns set to 'NA').

### write_reference_fasta(reference_df, file, taxonomy_file = NULL, rank_system = NULL)

Write a Reference Data Frame to FASTA Format

Exports a 'reference_df' (from 'fetch_ncbi_reference_sequences()' or 'read_reference_fasta()') to a FASTA file compatible with BLAST, CRABS, Obitools, and other external tools. Optionally writes a companion taxonomy TSV in the same positional format accepted by 'read_reference_fasta()', making the export fully round-trippable.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with columns 'composite_id', 'sequence', and at least one taxonomy column from 'rank_system'. Output of 'fetch_ncbi_reference_sequences()', 'read_reference_fasta()', or 'read_crabs_output()'. file: Character. Output path for the FASTA file (e.g., '"reference.fasta"'). |
| file | yes |  |  |
| taxonomy_file | no | NULL | Character or 'NULL'. If not NULL, write a companion 2-column taxonomy TSV to this path. The file can be passed to 'read_reference_fasta()' as 'taxonomy_file'. |
| rank_system | no | NULL | Character vector of taxonomy columns to include, coarse to fine. Defaults to all taxonomy-like columns found in 'reference_df' (everything except 'composite_id' and 'sequence'). |

**Value:** Invisibly returns 'reference_df'. Called for its side-effect of writing files.

## Quick Start

``` r
library(TaxaLikely)

# 1. Fetch reference sequences from NCBI (National Center for
# Biotechnology Information, U.S. National Library of Medicine,
# National Institutes of Health, Bethesda, Maryland)
reference_df <- fetch_ncbi_reference_sequences(
  taxa = c("Fundulidae", "Gobiidae"),
  barcode_term = "12S",
  rank = "family"
)

# 2. Build pairwise distance matrix
ref_matrix <- build_sequence_matrix(reference_df)

# 3. Screen for mislabeled references (TaxaMatch) -- see "Detecting Mislabeled
#    References" below for the full pattern
# 4. Train the likelihood model
model <- train_likelihood_model(ref_matrix)

# 5. Apply model to match data (from TaxaMatch)
result <- evaluate_likelihoods(match_df, model)
likelihoods <- result$likelihoods
# Columns: observation_id, taxon_name, hypothesis_type,
#           score_likelihood, score_likelihood_mean, score_likelihood_sd,
#           score_likelihood_cov, score_likelihood_evidence, h2_delta_source
```

