# CONTEXT: TaxaLikely

**Convert Match Scores to Likelihoods for Taxonomic Assignment**

Trains a hierarchical Bayesian model on reference-vs-reference match scores (DNA percent identity, image similarity, acoustic scores) and uses it to convert per-observation match scores into likelihoods. For each observation (observation_id), produces score_likelihood, score_likelihood_mean, and score_likelihood_sd across candidate taxa - the columns required by TaxaAssign. Also provides reference database quality tools: detecting mislabeled references and auditing taxonomic completeness. Part of the TaxaID ecosystem.

Version 1.0.0. 33 exported function(s).

## Functions

### annotate_reference_support(x, model, taxon_col = "consensus_taxon", rank_col = "consensus_rank", hypothesis_type_col = NULL, platform_col = NULL, lineage_cols = NULL, prefix = "winner")

Annotate Calls With How Much Reference Data Stood Behind Them

Appends four information-only columns reporting how much per-species reference data the trained likelihood model had for each row's taxon. Nothing in TaxaID reads them: there is no threshold, filter, gate or re-ranking on them anywhere. *A low count does not imply the call is wrong*, and a high one does not imply it is right - thinly referenced and correctly called is an ordinary combination. Always read '<prefix>_reference_basis' alongside a count, because 'NA' has five different reasons and one of them means thinner than any number, not better.

| Param | Required | Default | Doc |
|---|---|---|---|
| x | yes |  | Data frame of calls or hypotheses, one row per thing to annotate. Anything with a taxon-name column works, including a TaxaAssign::posterior_consensus() output, a per-observation posterior table, or an evaluate_likelihoods $likelihoods frame. |
| model | yes |  | A taxa_model_params object from train_likelihood_model -- the model that actually scored x -- or, when platform_col is given, a named list of such models whose names are the platform values appearing in that column. Any list carrying a conforming H1_Lookup is accepted, so a model restored from a cache that lost its class attribute still works. |
| taxon_col | no | "consensus_taxon" | Character. Column in x holding the taxon name to look up (default "consensus_taxon"). For a consensus table this is the published call; for a hypothesis table, the hypothesis. |
| rank_col | no | "consensus_rank" | Character or NULL. Column holding that taxon's rank (default "consensus_rank"). Rows whose rank is not one the model fits per-species rows at get "rank_not_in_model" without a name lookup, which is what separates a genus-level or rank-ring call from a species the model simply never saw. NULL, or a column absent from x, skips the rank check and relies on the name lookup alone. |
| hypothesis_type_col | no | NULL | Character or NULL (default). Column holding hypothesis_type. Any value beginning "unreferenced_" -- "unreferenced_species" and its genus, family, order and class counterparts -- is a hypothesis about something that is not in the reference set, so it has no reference sequences by construction and gets "unreferenced_hypothesis". Every other value, including "suppressed_candidate", is looked up normally. Supply this whenever the data has it. Most unreferenced-species hypotheses carry a real binomial at species rank, and without this column they match no lookup key and are reported as "no_model_row" -- which says "too thin for its own row" about a taxon that was never expected to have one. For a consensus table, which has no hypothesis_type of its own, join it from the hypothesis the consensus node came from. |
| platform_col | no | NULL | Character or NULL (default). Column naming which sequencing platform's model scored each row. Supply it with a named list of models whenever a marker was trained per platform; omitting it when the models differ silently reports one platform's numbers for all of them. |
| lineage_cols | no | NULL | Character vector or NULL (default). Lineage columns in x, finest rank first, used to reproduce the ancestor fallback evaluate_likelihoods applies when a candidate name is not itself a lookup key: the first ancestor name that is a key supplies the parameters, and the row is marked "model_row_via_lineage" so it is never mistaken for a direct species match. NULL disables the fallback, which under-reports support for exactly those rows. |
| prefix | no | "winner" | Character. Prefix for the four new column names (default "winner"). Annotate two taxon columns of the same table by calling twice with different prefixes. |

**Value:** 'x' with four columns added, named for 'prefix': '<prefix>_n_references' Integer. The number of per-species training observations the model fitted this taxon's mean from ('H1_Lookup$n_obs_species'), or 'NA' when no per-species row applies. What one observation counts depends on the 'pair_retention' policy used by 'build_sequence_matrix': one per reference sequence under '"best_per_partner"' or '"best_per_class"', one per reference PAIR under '"all"'. A trained model does not record which policy built its matrix, so this function cannot state the unit and neither should a reader who does not know the build. '<prefix>_reference_weight' Numeric in (0, 1). The empirical-Bayes weight the model gave this species' own mean ('H1_Lookup$shrink_w_score'); the remainder went to the global mean. Within one model this is a monotone function of the count and carries no extra per-row information - its value is that it is comparable ACROSS markers and models, which a raw count is not, because it measures the count against that model's own fitted between-species and within-species variance. '<prefix>_reference_basis' Character, one of '"model_species_row"' (a direct name match: the count is this taxon's own), '"model_row_via_lineage"' (an ancestor's row supplied the parameters, so the count is the ANCESTOR's, not this taxon's), '"no_model_row"' (the rank is one the model fits but this name has no row: fewer observations than the model's minimum, typically one reference sequence, scored against the global mean - thinner than any reported count), '"rank_not_in_model"' (the row is coarser than the model's per-species rank, as a genus-level call or a rank-ring hypothesis is, so no per-species count applies), '"unreferenced_hypothesis"' (a hypothesis about a taxon absent from the reference set, which has no reference sequences by construction - distinct from '"no_model_row"', which is about a taxon that IS in the reference set but too thinly for its own row), or '"no_taxon"' (the taxon name is 'NA'). '<prefix>_at_model_max' Logical. 'TRUE' when the count equals the largest count anywhere in this model's 'H1_Lookup'. When the matrix was built with 'build_sequence_matrix(' 'max_seqs_per_taxon = )', that maximum IS the cap and these rows are censored: the count means "this many or more", the true totals are unknown, and the difference between two such rows is not evidence about either. The share at the maximum can be large, so this is not a corner case. With no cap in the build, the column instead just marks the best-referenced species, and nothing is censored - which of the two applies is a fact about the caller's build that a trained model does not record. 'NA' where the count is 'NA'.

### apply_coverage_constraints(likelihood_df, census_result, penalty_factor = 0, constraint_behavior = c("relabel", "zero"))

Apply taxonomic completeness constraints to likelihood results

Suppresses or relabels the '"unreferenced_species"' hypothesis for genera confirmed to be fully sampled in the reference database. If a genus has no unsampled species, a new undescribed species from that genus is impossible - so the '"unreferenced_species"' likelihood should either be zeroed (hard constraint) or relabeled to capture the alternative biology.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_df | yes |  | Data frame returned by evaluate_likelihoods(). |
| census_result | yes |  | Data frame with columns taxon_name (the group name, e.g. genus label), rank (e.g. "genus"), and status ("complete" or "closed" for fully-sampled groups; any other value leaves the hypothesis untouched). To build this from audit_barcode_coverage(): cov <- audit_barcode_coverage(match_df, barcode_term = "12S", target_rank = "genus") census_result <- dplyr::mutate( cov$census, taxon_name = group, rank = "genus", status = ifelse(is_complete, "complete", "incomplete") ) |
| penalty_factor | no | 0 | Numeric in [0, 1] (default 0.0). Multiplier applied to score_likelihood, score_likelihood_mean and score_likelihood_sd for constrained hypotheses when constraint_behavior = "zero". Ignored when constraint_behavior = "relabel" (the default), whose weight is moved at posterior time instead. |
| constraint_behavior | no | c("relabel", "zero") | Character scalar: "relabel" (default) or "zero". See Details above and "Census confidence" below. |

**Value:** 'likelihood_df' with an added 'constraint_applied' column and updated likelihood and/or 'hypothesis_type' columns: '"zero"' mode 'score_likelihood', 'score_likelihood_mean' and 'score_likelihood_sd' multiplied by 'penalty_factor'; 'constraint_applied' set to '"census_closed_genus"'. '"relabel"' mode 'hypothesis_type' changed to '"unresolved_species"', likelihoods unchanged, 'constraint_applied' set to '"census_closed_genus_relabeled"' - the marker 'TaxaAssign::compute_posterior()' reads to move the row's posterior onto the genus's referenced species. Rows not meeting the constraint have 'constraint_applied = NA'.

#### Details

Behaviour modes (controlled by constraint_behavior):

- "relabel" (default): hypothesis_type is changed from "unreferenced_species" to "unresolved_species"; the likelihoods are left as they are. The row's weight is not removed here but MOVED later: TaxaAssign::compute_posterior() passes a relabeled row's posterior to the genus's referenced species in the same observation, in proportion to their own posteriors, so the genus keeps exactly the mass it had and only its split among the referenced species changes. That is the elimination the census licenses: a genus every one of whose species is referenced has no unsequenced congener for this row to stand for, so what the sequence attributes to "an unsequenced member of this genus" belongs to its sequenced members. Moving the weight (rather than zeroing it here) keeps it inside the genus: zeroing the likelihood and renormalising over every hypothesis would hand the placeholder's share to the OTHER genera and families in the observation as well. (Grass carp, Ctenopharyngodon idella, at Great Lakes: the placeholder held 0.51 of the posterior against the species' 0.41; moved, the species holds 0.93 and resolves; zeroed, it held 0.85 and the call fell to the family.) The posterior step needs the constraint_applied column this function adds and a genus column (or a species binomial) on the rows; a consensus run on these likelihoods WITHOUT that step sees the placeholder at its full weight, as before the relabel. Ambiguity AMONG the referenced species is carried by their own rows and by the consensus's rank walk, not by this placeholder.

- "zero": score_likelihood, score_likelihood_mean and score_likelihood_sd are multiplied by penalty_factor (default 0.0 = hard zero) and the hypothesis_type is left as it was. The placeholder's share is then renormalised over every hypothesis in the observation, inside and outside the genus. The SD is scaled too so the Monte Carlo path of TaxaAssign::compute_posterior() honours the zero (a zero mean with a positive SD still draws positive likelihoods). Either way, see the "Census confidence" section below: the census is an NCBI-query estimate, and a lookup that FAILED is reported as lookup_failed/incomplete (never complete), so a failure can only leave a placeholder in play, never remove a real one.

#### Census confidence

census_result$status (built from audit_barcode_coverage()'s is_complete) reflects what an NCBI taxonomy-tree query returned for the genus, not a verified, ground-truth-complete species enumeration. A genus can look "complete" because of a query gap rather than genuine completeness -- e.g. a recently described species not yet indexed in NCBI taxonomy, an unresolved synonym, or a taxonomic renaming the query missed (audit_barcode_coverage()'s own docs already note the species_list parameter exists specifically to supply a more complete enumeration, e.g. from FishBase, when this is a concern). constraint_behavior = "zero" treats status == "complete" as certain and permanently discards the "unreferenced_species" hypothesis for that genus -- a genuinely novel detection in a falsely-"complete" genus is then deterministically misassigned, with no way for downstream evidence to recover it. "relabel" (the default) is deliberately conservative instead: it never destroys likelihood mass, only changes how the hypothesis is labeled, so a mistaken census can, at worst, cost genus-level resolution rather than create a wrong answer with no exit.

### assign_scores(hypotheses_df, score_type, score_col = "score_original", score_sharpness = 0.1)

Assign score_likelihood values to a hypotheses data frame

Converts raw match scores (or absence of scores) into the 'score_likelihood' column required by 'TaxaAssign::compute_posterior()'. Works on the expanded hypotheses data frame produced by 'unreferenced_candidates()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| hypotheses_df | yes |  | Data frame produced by unreferenced_candidates(). Must contain observation_id and hypothesis_type. For all score_type values except "none", must also contain the column named by score_col for "specific_candidate" rows. |
| score_type | yes |  | Character scalar. One of "none", "direct", "probability", "similarity_softmax", or "similarity". |
| score_col | no | "score_original" | Character. Name of the raw score column in hypotheses_df (default "score_original"). Ignored when score_type = "none". |
| score_sharpness | no | 0.1 | Positive numeric (default 0.1). Exponent scaling factor for score_type = "similarity_softmax" only. Larger values create sharper discrimination between candidates; smaller values produce more uniform likelihoods. |

**Value:** For 'score_type = "similarity"': the input data frame with 'score_norm' (H1 rows only) and 'score_method = "similarity"' added. See the '"similarity"' entry under '@details' above - real callers use 'evaluate_likelihoods()' directly instead of continuing from this output. For all other 'score_type' values: a data frame with one row per 'observation_id' x hypothesis (H1 aggregated to one row per 'taxon_name', H2/H3/H4 unchanged), with columns 'score_likelihood', 'score_likelihood_mean' (= point estimate), 'score_likelihood_sd' (= 0), and 'score_method' added.

#### Details

score_type values:

- "none": No score column available. All rows receive score_likelihood = 1.0 (uniform / degenerate likelihoods). Posteriors are proportional to priors.

- "direct": Passes score_col through unchanged as score_likelihood. Rows with NA scores receive score_likelihood = 1.0. Intended for use after restore_suppressed_candidates(), which pre-imputes scores for restored rows. No per-observation aggregation is performed.

- "probability": Neural-net softmax outputs (e.g., BirdNET multi-candidate output, iNaturalist CV scores) already on a 0-1 scale. H1 scores are ratio-normalized (/ max) so the best candidate always receives score_likelihood = 1.0. H2/H3 receive the median H1 score_likelihood among same-genus (H2) or same-family (H3) candidates; overall median as fallback.

- "similarity_softmax": Similarity scores (0-100 or 0-1) with no trained statistical model available. Scores are normalized to (0,1) via .normalize_scores(), exponentiated (e^{sharpness \times score_{norm}}), then ratio-normalized. H2/H3 are anchored at the median softmax-normalized score of same-genus (H2) or same-family (H3) H1 candidates. Appropriate for the LLM shortcut pathway when no trained model exists.

- "similarity": Similarity scores destined for the bivariate-normal model. This function only adds score_norm to H1 rows and sets score_method = "similarity"; it does not write score_likelihood. In practice this pathway is not how the bivariate-normal model is actually reached -- every real caller trains a model with train_likelihood_model() and calls evaluate_likelihoods() directly on the original match_df (see that function's own @param match_df), which internally performs the same logit transform / H1 selection this score_type value stages. score_type = "similarity" is retained as a documented, tested contract of this function, not as a recommended entry point.

Normalization convention: all score_likelihood values are likelihood ratios (divided by the maximum H1 likelihood), not probabilities. H2/H3/H4 rows are added after H1 normalization so that H1 values are unaffected by the number of unreferenced hypotheses. TaxaAssign::compute_posterior() normalizes posteriors, so the absolute scale of likelihoods does not matter.

### audit_acoustic_coverage(plausible_species, reference_species, match_df = NULL, xc_recordings = FALSE)

Audit Acoustic Reference Coverage for a Species List

Checks which plausible species at a site are absent from an acoustic classifier's known species list (e.g., BirdNET's built-in list or a custom Xeno-canto model). A species absent from the reference can never appear as a scored candidate - it is an *unreferenced species* in the acoustic context.

| Param | Required | Default | Doc |
|---|---|---|---|
| plausible_species | yes |  | Character vector. Species expected to occur at the sampling site (e.g., from an LLM call, GBIF query, or expert list). Should be binomial scientific names. |
| reference_species | yes |  | Character vector. Species in the classifier's known list (e.g., the BirdNET species list, or the set of species used to train a custom Xeno-canto model). Names are matched case-insensitively after trimming whitespace. |
| match_df | no | NULL | Data frame or NULL. Optional. If supplied, species already present in the match data (i.e., confirmed candidates from the classifier) are annotated as in_match_data = TRUE in the census output. Use TaxaMatch::standardize_match_data() output or raw TaxaMatch::read_birdnet_output() output. The species column is auto-detected from "species" or "taxon_name". Default NULL. |
| xc_recordings | no | FALSE | Logical. If TRUE, queries the Xeno-canto v3 API for the number of recordings available for each species in plausible_species and adds an n_recordings column to the census. Requires an internet connection, a registered Xeno-canto API key set via the XC_API_KEY environment variable (register at xeno-canto.org/explore/api), and adds approximately 1 second per species. Default FALSE. |

**Value:** A named list with two components: 'census' Data frame with one row per entry in 'plausible_species': 'species' Species name (from 'plausible_species'). 'in_reference' Logical. 'TRUE' if the species is in 'reference_species'. 'unreferenced' Logical. 'TRUE' if the species is absent from 'reference_species' (can never appear as a candidate detection). 'in_match_data' Logical. 'TRUE' if the species appeared in 'match_df'. 'NA' when 'match_df = NULL'. 'n_recordings' Integer. Number of Xeno-canto recordings for the species. 'NA' when 'xc_recordings = FALSE' or the query fails. Even a species present in the BirdNET list may be poorly classified if it has very few training recordings. 'unreferenced' Character vector of species names absent from 'reference_species'. Pass directly to 'TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)' to build H2 hypotheses for these species.

#### Details

This is the acoustic analog of audit_barcode_coverage(), but far simpler: no NCBI API calls are needed. Coverage is determined by a plain set membership check against reference_species.

#### Scope

Designed for acoustic (bird sound) and image (camera trap) data where the classifier has a fixed known species list. For DNA eDNA data, use audit_barcode_coverage() instead (barcode sequence availability in NCBI is the relevant coverage concept, not presence in a classifier list).

### audit_barcode_coverage(match_df, barcode_term, species_list = NULL, min_len = NULL, max_len = NULL, max_date = NULL, target_rank = "genus", cache_dir = tools::R_user_dir("TaxaLikely", "cache"), ncbi_api_key = NULL, max_nuccore = 5000L, exclude_predicted = TRUE, on_lookup_failure = c("warn", "error"))

Identify unreferenced species for barcode-based taxonomic assignment

An *unreferenced species* is a described taxon that has *no barcode sequence* for the target marker in any reference database. Because TaxaMatch can only return taxa that have reference sequences, an unreferenced species can never appear as a named match candidate - even if it is the true source of the observed sequence. Adding unreferenced species as explicit hypotheses allows the LLM (via 'TaxaAssign::assign_taxa_llm()') to evaluate their geographic plausibility alongside the named match candidates.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame with at least a target_rank column (e.g. "genus") and a "species" column. Species present in match_df are treated as a skip-list: they have reference sequences by definition and are excluded from the barcode-count queries. Pass the actual match object (e.g. match_obj / match_obj_restored from restore_suppressed_candidates()) here -- not a length-curated reference_df built for build_sequence_matrix()/train_likelihood_model(). A species whose only reference sequence is a long record (e.g. a complete mitogenome) is routinely dropped from a length-curated training set even though BLAST matched it correctly; passing that curated set here makes audit_barcode_coverage() report the species "unreferenced" despite it already being a specific_candidate. See Details. |
| barcode_term | yes |  | Character scalar or vector. One or more marker search terms (e.g. "12S", c("12S", "MiFish")). Multiple terms are OR-ed. |
| species_list | no | NULL | Optional character vector of binomial species names. If supplied, used instead of the NCBI taxonomy query to determine which species exist in each genus. Useful when GBIF, FishBase, or WoRMS provides more complete coverage than NCBI taxonomy for your taxon group. Invalid names (sp., cf., uncultured, etc.) are silently dropped. |
| min_len | no | NULL | Integer or NULL. Minimum sequence length (SLEN filter). NULL uses a barcode-specific default (see Details). |
| max_len | no | NULL | Integer or NULL. Maximum sequence length. NULL uses the barcode-specific default. |
| max_date | no | NULL | Optional character scalar. Restricts unreferenced species detection to sequences present in NCBI on or before this date, embedded as a [PDAT] range in the query term. Format: "YYYY", "YYYY/MM", or "YYYY/MM/DD". NULL uses the current state of GenBank. Set this to match the build date of your reference library. |
| target_rank | no | "genus" | Character scalar. Rank column in match_df (default "genus"). |
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Directory for per-genus checkpoints. Default: tools::R_user_dir("TaxaLikely", "cache"). Pass NULL to disable checkpointing. If a checkpoint from a previous interrupted run is found (matched by call signature), processing resumes automatically from where it stopped. The checkpoint is deleted on clean completion. |
| ncbi_api_key | no | NULL | Optional NCBI API key. Raises the rate limit from 3 to 10 requests per second. Can also be set via ENTREZ_KEY environment variable (Sys.setenv(ENTREZ_KEY = "your_key"); confirm with Sys.getenv("ENTREZ_KEY")). |
| max_nuccore | no | 5000L | Integer. Maximum NCBI nucleotide IDs fetched per genus for the reverse barcode check. Default 5000; increase for extremely sequence-rich genera if some represented species are suspected to be missed. |
| exclude_predicted | no | TRUE | Logical. If TRUE (default), computationally predicted sequences (NCBI title prefix "PREDICTED:", typically XR_ and XM_ RefSeq accessions) are excluded from the barcode check. Predicted sequences are absent from curated databases (SILVA, PR2, MIDORI) used by metabarcoding labs and do not represent experimentally validated barcodes -- counting them inflates has_seqs_not_in_ref and incorrectly suppresses unreferenced-species hypotheses for those taxa. Set FALSE only if you explicitly need to count predicted sequences. Mirrors the blacklist_regex = "predicted" default in fetch_ncbi_reference_sequences(). |
| on_lookup_failure | no | c("warn", "error") | "warn" (default) or "error". What to do when NCBI could not be asked about one or more groups (a failed search, a failed summary batch, or a failed taxid resolution). Such a group is reported with lookup_failed = TRUE in the census, is never checkpointed, and contributes nothing to unreferenced -- so the returned set is INCOMPLETE, not a census. "warn" names the groups in one consolidated warning and message and attaches them as attr(x, "lookup_failures"); "error" stops instead, which suits an unattended run whose downstream steps would otherwise cache a truncated set as if it were complete. Same shape as fetch_ncbi_reference_sequences()'s on_count_failure. |

**Value:** A named list: 'census' Data frame, one row per genus: 'group', 'total' (described species), 'in_reference' (in 'match_df'), 'has_seqs_not_in_ref' (experimental barcode sequences exist in NCBI but not in the reference - a completeness gap), 'has_predicted_only' (only computationally predicted sequences found; 'NA' when classification was not performed), 'unreferenced' (no barcode sequences found; when 'exclude_predicted = TRUE' (default), predicted-only species are included here), 'is_complete' (TRUE when both gaps are zero), and 'lookup_failed' (TRUE when NCBI could not be asked about this group; its species are then absent from 'unreferenced', 'is_complete' is FALSE, and the group is named in 'attr(x, "lookup_failures")' - see 'on_lookup_failure'). 'unreferenced' Character vector of unreferenced species names, suitable for 'TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)'.

#### Details

Example: a 12S eDNA read from Fundulus parvipinnis (no reference sequence) matches most closely to Fundulus lima (has reference). Without unreferenced species insertion, F. parvipinnis can never be the top hypothesis. With unreferenced species insertion, the LLM recognises that F. parvipinnis is the native Southern California congener and ranks it above F. lima.

##### Unreferenced species definition

For each genus represented in match_df, the function:

- Retrieves all described species in the genus (from NCBI taxonomy, or from a user-supplied species_list).

- Removes species already in match_df -- these have reference sequences by definition and are skipped (skip-list optimisation).

- For each remaining species, queries NCBI nucleotide with retmax = 0 (count only) to check whether a barcode sequence exists.

- Species with count = 0 are unreferenced.

- Species with count > 0 but absent from match_df represent a reference completeness gap (reported separately in the census).

##### Species list completeness

NCBI taxonomy is the default species source but is not exhaustive: some described species appear only in GBIF, FishBase, WoRMS, or other authorities. Species absent from the chosen source are also unreferenced but will be missed. Supply a more complete list via species_list when taxonomic completeness is critical (e.g. well-studied vertebrate genera).

##### Length defaults by barcode

- MiFish / 12S: 100--600 bp

- Teleo: 50--300 bp

- 16S: 100--700 bp

- COI: 300--900 bp

- CytB: 200--900 bp

- ITS2: 100--600 bp

- ITS: 100--900 bp

- rbcL: 400--800 bp

- matK: 600--1100 bp

- 18S: 100--2000 bp

- trnL: 10--300 bp

- (unrecognised): 100--2000 bp (fallback, with message)

##### Common mistake: passing a length-curated reference instead of the match object

match_df must represent every species with a usable reference sequence, independent of amplicon length -- because BLAST itself is not length-constrained. Confirmed example: a 12S BLAST hit for Mustelus mosis against accession with subject_length 16755bp (a complete mitogenome) and alignment_length 174bp -- a correct specific_candidate H1. That same accession is routinely excluded from a reference_df built for build_sequence_matrix(), since aligning a 16.7kb mitogenome against ~170bp barcode fragments would corrupt the pairwise-distance training set. If that length-curated reference_df is then reused as match_df here, M. mosis has no entry in the skip-list, the barcode-length-restricted NCBI query correctly finds no short-format sequence for it, and it is reported unreferenced -- contradicting the match object where it is already a named H1 candidate. Symptom: a species appears in both match_obj$taxon_name and this function's $unreferenced output. Fix: pass the match object, not the training reference.

##### API strategy (reverse search)

Species enumeration uses the NCBI taxonomy subtree (three taxonomy API calls per genus) when species_list is NULL. Barcode availability is checked via a reverse search: one genus-level NCBI nucleotide query (capped at max_nuccore hits) followed by a batched entrez_summary on the nuccore records to retrieve title and taxid simultaneously, then a batched taxonomy entrez_summary to resolve species names. This requires only ~4 fixed API calls per genus regardless of how many candidate species exist, and is substantially faster than per-species retmax = 0 queries for species-rich genera. The date filter is embedded directly in the query term as a [PDAT] range. Sequences with a "PREDICTED:" title prefix (typically XR_/XM_ RefSeq accessions) are classified separately; see exclude_predicted.

### audit_inat_coverage(species_list, match_df = NULL, cv_threshold = 100L, api_token = Sys.getenv("INAT_API_TOKEN"), verbose = FALSE)

Audit iNaturalist Reference Coverage for a Species List

For each species in 'species_list', queries the iNaturalist taxa API to retrieve the global observation count and determine whether the species is likely present in iNaturalist's computer vision (CV) training data. Species with fewer than 'cv_threshold' observations are treated as *unreferenced* for the image classification pathway - they can never appear as CV candidates and must be handled as undetected taxa in 'TaxaAssign::join_priors()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| species_list | yes |  | Character vector. Species names to check (typically the set of prior taxa, or prior taxa absent from the match object). Non-binomial names are silently skipped. |
| match_df | no | NULL | Data frame or NULL. Optional. If supplied, species already present in the image match data are annotated as in_match_data = TRUE. The species column is auto-detected from "taxon_name" or "species". Default NULL. |
| cv_threshold | no | 100L | Integer. Minimum global observation count on iNaturalist for a species to be considered present in the CV training data. Default 100L. The exact iNaturalist threshold is not publicly documented; 100 research-grade observations is a widely cited approximation. Species below this threshold are flagged cv_model_included = FALSE and included in $unreferenced. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. Optional iNaturalist API token. When provided, increases the API rate limit. Defaults to INAT_API_TOKEN environment variable; pass api_token = "" to query without authentication. |
| verbose | no | FALSE | Logical. If TRUE, prints a progress line for each species. Default FALSE. |

**Value:** A named list with two components: 'census' Data frame with one row per entry in 'species_list', containing: 'species', 'taxon_id', 'matched_name' (iNat accepted name), 'n_observations' (global iNat count), 'in_inat' (logical; species found in iNat), 'cv_model_included' (logical; 'n_observations >= cv_threshold'), 'unreferenced' (logical; 'TRUE' when absent from iNat or below the CV threshold), 'in_match_data' (logical; 'NA' when 'match_df = NULL'). 'unreferenced' Character vector of species either not found in iNaturalist or below 'cv_threshold'. Pass to 'TaxaLikely::unreferenced_candidates()' to build H2/H3 hypotheses.

#### Details

This is the image analog of audit_barcode_coverage: both functions take a list of prior species, identify which lack classifier references, and return the unreferenced set for downstream handling. Unlike audit_barcode_coverage(), no authentication is required (the iNaturalist taxa API is publicly accessible); the optional api_token only relaxes rate limits.

Rate limiting: A 0.3-second pause is inserted between API calls. For 100 species, expect approximately 30 seconds.

CV threshold interpretation: cv_model_included = FALSE means the species is too rare on iNaturalist for the CV model to have learned a reliable image signature. Such species are photographed too infrequently for training. In practice, marine invertebrates, algae, and many protists fall below this threshold even when present on iNat, while common birds and butterflies almost always exceed it.

Backbone note: iNaturalist uses its own taxonomy; matched names may differ from GBIF. After retrieving results, run TaxaMatch::convert_taxonomy_backbone() if you need GBIF-aligned names.

### audit_reference_coverage(reference_df, target_rank = "genus", ncbi_api_key = NULL)

Audit reference database taxonomic completeness via NCBI taxonomy

For each group at 'target_rank' (e.g., each genus) in the reference database, queries the NCBI taxonomy database to count how many accepted species exist, then compares with the species present in your reference. Returns a census summary and a vector of unreferenced species - taxa known to exist at NCBI but absent from your reference.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame containing at least two columns: one named target_rank (e.g., "genus") and one named "species". |
| target_rank | no | "genus" | Character scalar -- the rank to audit (default "genus"). Must be a column in reference_df. |
| ncbi_api_key | no | NULL | Optional NCBI API key string (increases rate limit from 3 to 10 requests/second). Can also be set via the ENTREZ_KEY environment variable before calling this function. |

**Value:** A named list: 'census' Data frame with one row per group: 'group', 'total' (true species count per NCBI), 'have' (in reference), 'missing_count', and 'is_complete' (logical). 'unreferenced' Character vector of species names present at NCBI but absent from the reference.

#### Details

Unreferenced species inform the H2 (unreferenced species) hypothesis: genera with many unreferenced species have higher H2 probability mass. Fully-sampled genera can have their H2 hypothesis suppressed via apply_coverage_constraints().

#### Scope

This function is designed for DNA sequence reference databases and queries NCBI taxonomy to enumerate described species. It is not appropriate for acoustic or image reference data, where coverage is determined by whether a species appears in the model training set rather than in NCBI. For barcode-specific coverage (checking NCBI nucleotide for sequence availability), use audit_barcode_coverage() instead.

### build_sequence_matrix(reference_df, rank_system = NULL, max_dist = 0.25, min_seq_len = 100L, max_seq_len = 2000L, filter_unnamed = TRUE, max_seqs_per_taxon = NULL, barcode_term = NULL, verbose = TRUE, by_genus = FALSE, max_foreign_reps_per_genus = 20L, pair_retention = c("all", "best_per_partner", "best_per_class"), min_pair_coverage = 0.8, memory_budget_fraction = 0.7, seed = NULL)

Build a pairwise match-score matrix from reference sequences

Aligns DNA sequences using 'DECIPHER::AlignSeqs()', computes pairwise distances with 'DECIPHER::DistanceMatrix()', converts distances to match scores ('p_match = 1 - distance'), and joins taxonomy metadata. The resulting data frame is the input to 'train_likelihood_model()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with one row per reference sequence. Must contain: composite_id: Unique sequence identifier (character). sequence: DNA string (character, IUPAC alphabet accepted). rank columns: One column per rank in rank_system (e.g., genus, species). |
| rank_system | no | NULL | Character vector of rank names coarse to fine (e.g., c("family", "genus", "species")). Default NULL auto-detects from columns in reference_df. |
| max_dist | no | 0.25 | Numeric (default 0.25). Pairs with distance above this threshold are dropped to save memory. Roughly, 0.25 ~= 75% identity. The 75% identity threshold is a standard floor for retaining distantly related taxa in barcode reference databases. |
| min_seq_len | no | 100L | Integer (default 100). Sequences shorter than this are discarded before alignment. Ignored if barcode_term is supplied and this argument is left at its default -- see barcode_term below. |
| max_seq_len | no | 2000L | Integer (default 2000). Sequences longer than this are discarded before alignment. Ignored if barcode_term is supplied and this argument is left at its default -- see barcode_term below. |
| filter_unnamed | no | TRUE | Logical (default TRUE). If TRUE, sequences whose finest-rank taxonomy column (the last element of rank_system, typically species) is blank ("") or NA are removed before alignment. Blank names produce spurious within-species pairs -- two unidentified sequences both labelled "" are classified as conspecific even though they may represent entirely different taxa. In a broad 18S reference database this can account for the majority of apparent within-species pairs. Set to FALSE only if blank finest-rank values are intentional. |
| max_seqs_per_taxon | no | NULL | Integer or NULL (default NULL). If supplied, at most this many sequences are retained per finest-rank taxon before alignment, chosen by random sampling. Pass seed to make that draw reproducible; without it the draw uses the caller's RNG state. This prevents heavily-sequenced model organisms or domestic species from dominating the within-species distribution and thereby distorting model training. For typical vertebrate barcode databases a value of 10L-20L is sufficient; the resulting within-species pair counts per taxon are at most max_seqs_per_taxon * (max_seqs_per_taxon - 1) / 2. NULL disables the cap (current behaviour). |
| barcode_term | no | NULL | Character or NULL (default NULL). When supplied AND min_seq_len/max_seq_len are both left at their defaults, resolves the length window via TaxaTools::resolve_barcode_lengths(barcode_term) instead of using the generic [100, 2000] default. Explicit min_seq_len/max_seq_len always override this, matching resolve_barcode_lengths()'s own override convention. This exists because the generic default length window does NOT guarantee every retained sequence covers the same amplicon window -- only that it is a plausible barcode-length fragment of some kind. A broad NCBI free-text search (e.g. barcode_term = "12S" at fetch time) can return sequences describing a genomically different stretch of the same gene (older primer sets, broader mitochondrial fragments) that still happen to pass a length filter -- silently mixing two different genomic windows into what looks like one self-consistent H1/H2 training set (the documented "Paralabrax footgun": a real 0% MiFish-primer-site hit rate on sequences that had already passed the generic length filter). Passing a specific, registered primer variant here (e.g. "MiFishU", not just "12S") gives the strongest guarantee, since that resolves to the literature-verified real PCR amplicon length rather than a broader per-gene range; a bare marker name (e.g. "12S") only guarantees "roughly the right marker," not amplicon-window comparability, and does not by itself close this gap. See the sebastes_chromis_confirmation.R diagnostic (TaxaID_dev repository) for the case this was found in. A reference_df returned by match_reference_region() (it carries a trim_path column) is exempt from this window: its sequences are already cut to the ESVs' own span, and their own length range is used instead. |
| verbose | no | TRUE | Logical (default TRUE). Passed straight through to DECIPHER::AlignSeqs()/DECIPHER::DistanceMatrix()'s own native progress reporting (percent-complete, ETA) for the two steps that dominate wall time on a large reference set (alignment cost grows worse than linearly in sequence count, so a large reference database can run for hours with no visible signal of progress without it). This function's OWN message() calls (length-filter counts, rank-system auto-detection, timing summaries) are unaffected either way -- only DECIPHER's own in-progress display is controlled by this parameter. FALSE gives a fully-silent run (e.g. for a non-interactive/logged batch run where a live progress bar is meaningless). |
| by_genus | no | FALSE | Logical (default FALSE; see @section Per-genus alignment below). TRUE replaces the single whole-set DECIPHER::AlignSeqs() call with many small per-genus alignments (each augmented with up to max_foreign_reps_per_genus other genera's chosen representatives) plus one small cross-genus-representative alignment -- same output shape, much better scaling on a reference set with many genera. Requires "genus" in rank_system (errors if absent); a sequence with a blank/NA genus value is dropped with a message rather than aborting the run (a real broad fetch legitimately has some genus-unresolved accessions -- e.g. environmental samples). |
| max_foreign_reps_per_genus | no | 20L | Integer or NULL (default 20L). Only relevant when by_genus = TRUE -- caps how many OTHER genera's representative sequences get added to each genus's own augmented alignment (see @section Per-genus alignment below). NULL means no cap (every other genus's representative is added, regardless of how many genera exist) -- real-data validation found this costs MORE than whole-set alignment, and gets worse as genus count grows (a real 221-genus reference set took ~40 minutes uncapped vs ~10 minutes for whole-set), since the added cost scales with the SQUARE of genus count. A finite cap keeps the added cost linear in genus count instead (genera x cap, not genera x (genera - 1)) -- each genus draws an INDEPENDENT random subset of cap other genera's representatives (not one subset shared across every genus, which would starve whichever genera never happen to fall inside it), so coverage stays roughly even across genera even though it is no longer exhaustive. 0L disables the augmentation entirely (representative-only alignment -- see the @section below for why that understates gap_logit). |
| pair_retention | no | c("all", "best_per_partner", "best_per_class") | "all" (default), "best_per_partner" or "best_per_class". Which pairs within max_dist are returned. "all" returns every pair. The other two return every within-species pair plus, for each sequence and each stratum of its cross-species partners, at most two pairs: the best-scoring one whose coverage clears min_pair_coverage, and the best-scoring one regardless of coverage. Under "best_per_partner" the stratum is the partner species inside the sequence's own genus and the partner family (or genus when no family rank is given) outside it; under "best_per_class" it is the pair type itself -- congeneric, confamilial or cross-family -- so a sequence keeps at most six cross-species pairs in total. See @section Pair retention for why both are exact for train_likelihood_model() and what each changes elsewhere. |
| min_pair_coverage | no | 0.8 | Numeric in (0, 1] or NULL (default 0.8). Only used when pair_retention is not "all": the coverage floor the retained best-clearing pair is chosen under. Must equal the min_pair_coverage later passed to train_likelihood_model() (whose default is also 0.8), or be NULL if training will use NULL; the value is recorded in the result's "pair_retention" attribute and train_likelihood_model() warns on a mismatch it can still see. |
| memory_budget_fraction | no | 0.7 | Numeric in (0, 1] or NULL (default 0.7). Before aligning, the size of the pair table is predicted and compared with this fraction of the memory currently available; when it will not fit, the function stops and names settings that would. NULL skips the check. The fraction is below 1 because the prediction covers the pair table and the working copies training makes of it, not the reference sequences themselves or the aligner's own structures. When pair_retention is not "all" the prediction is an upper bound the build will not reach, so it is reported and not enforced. See @section Memory. |
| seed | no | NULL | Integer or NULL (default NULL). When supplied, the random draws below are made from this seed and the caller's own RNG stream is handed back untouched, so the same reference_df and settings give the same matrix on every run. Three draws can occur: the max_seqs_per_taxon thinning, the choice of one representative per genus under by_genus, and the max_foreign_reps_per_genus cap. They decide which sequences train the calibration, so an unseeded build makes the calibration, and every likelihood resting on it, unreproducible whenever a cap is reached. NULL keeps the draws on the caller's RNG state, which is what check_cross_genus_sampling_noise() needs in order to measure how much the representative draw moves the estimate; a fixed default would make its replicates identical and report zero noise. For a production build, pass a seed here rather than calling set.seed() beforehand: measured across five production call sites, none honoured that older convention, and one appeared to while not doing so. |

**Value:** A data frame with one row per sequence pair within 'max_dist': 'id_x', 'id_y' 'composite_id' values for each pair member. 'p_match' Match score (1 - distance), range (0, 1]. 'coverage' Alignment coverage: number of positions where both sequences contribute a non-gap character, divided by the shorter unaligned sequence length. Range (0, 1]. Values near 1.0 indicate nearly complete overlap; values near 0.0 indicate highly gappy or partial alignments that produce unreliable match scores. A minimum coverage threshold can be applied directly (e.g. 'ref_matrix[ref_matrix$coverage >= threshold, ]') before calling 'train_likelihood_model()'; this package does not provide a dedicated threshold-calibration helper for it. {rank}.x, {rank}.y Taxonomy columns for each pair member.

#### Requirements

Packages DECIPHER and Biostrings must be installed (BiocManager::install("DECIPHER")). They are listed in Suggests because they are only needed for this one function.

#### Pair retention (pair_retention other than "all")

The pair table's size is dominated by same-genus cross-species pairs, which grow with the square of a genus's sequence count, so a species-rich genus with many sequences per species sets the memory ceiling for the whole build. Yet nothing downstream consumes those pairs as a distribution. train_likelihood_model() reads, per reference sequence, its best within-species match, its best same-genus cross-species match and its best cross-species match of any kind (each as the best pair clearing its coverage floor, with the unfloored best as fallback); the confusion-risk curves read the best match per pair type (within-species, congeneric, confamilial, cross-family); a singleton takes its single best partner. Every one of those is a maximum, and the maximum over a union of strata is the maximum of the per-stratum maxima -- so keeping the two best pairs per (sequence, partner stratum) reproduces each of them exactly and the trained model is identical to the one trained on "all". Within-species pairs are always kept in full: they are a few percent of the table, and TaxaMatch::corroborate_references_locally() counts distinct conspecific partners and their submission independence, which needs every one of them.

What changes: under "best_per_partner" the table is smaller by roughly the mean number of sequences per partner species inside a genus (bounded above by max_seqs_per_taxon), so same-genus rows grow as sequences times species per genus instead of sequences squared; under "best_per_class" they grow as sequences alone, and within-species pairs (quadratic per species, bounded by max_seqs_per_taxon) become the largest term. Alignment cost is unchanged either way. The row count N_Obs in the training data is unchanged (within-species pairs are complete). restore_suppressed_candidates() looks pairs up by accession: a query's direct pair with a specific candidate accession is present only when that accession is the query's best for its species, so restoration resolves more often at its species-pair and genus-model levels than at the direct-accession level, and its species-pair median is a median of per-query bests rather than of all pairs (under "best_per_class" restoration mostly resolves from the genus model). An accession screen run on the thinned table works unchanged, because it reads within-species pairs, which are complete; removing its "remove" accessions from the table afterwards costs only the sequences whose best partner for a stratum was a removed accession, which then have no runner-up for that stratum. check_cross_genus_sampling_noise() always builds with "all".

#### Per-genus alignment (by_genus = TRUE)

Whole-set alignment cost grows worse than linearly in sequence count, but train_likelihood_model() only consumes within-species pairs (H1), same-genus cross-species pairs (H2), and a pooled cross-genus sample (H3, coarse and never species-specific) -- none of which need one shared whole-set alignment, only same-scale genomic coordinates within whatever comparison they're drawn from.

by_genus = TRUE does many smaller alignments instead of one huge one: each genus's own sequences are aligned together (giving every H1/H2 pair unchanged), but that alignment ALSO includes a copy of up to max_foreign_reps_per_genus OTHER genera's chosen representative sequences, so every sequence, not just the genus's own representative, gets a real comparison against a real member of some (or, uncapped, every) other genus; a representative-only alignment would inflate the gap_logit feature for every non-representative sequence. A separate, small dedicated alignment of just the representatives (one per genus) supplies the representative-vs-representative pairs (excluded from the per-genus step to avoid computing them twice). Together these give H3 (and H2's pooled fallback for a genus with no real congener) a real cross-genus sample at a fraction of the whole-set cost; see max_foreign_reps_per_genus for why the cap matters. Both pieces are combined into one table with the same column shape this function always returns, so train_likelihood_model() needs no changes either way.

Each genus's own representative is chosen at RANDOM, not "first", since nothing guarantees reference_df's row order is unbiased. Use check_cross_genus_sampling_noise() to see how much that one random draw moves the cross-genus pair distribution before trusting a single run's H3 estimate on a new marker.

A pair between two NON-representative sequences from two DIFFERENT genera is never compared (recovering that would mean going back to whole-set cost). Validate against a marker with an existing, already-trusted whole-set-trained model before relying on this for a new one; do not assume the two approaches give numerically identical H1/H2/H3 parameters just because they consume conceptually the same pairs.

#### Memory

The result has one row per ordered pair of sequences within max_dist, and train_likelihood_model() holds several working copies of it, so on a broad reference set this table, not the alignment, is what runs out of memory. Its size follows from the reference set's genus composition: it grows with the square of the sequences in each genus and, with by_genus = TRUE, with the square of the number of genera (see estimate_sequence_matrix_size() for the formula).

Before aligning, the peak through training is predicted and compared with memory_budget_fraction of the memory available now (read from the operating system on macOS, Linux and Windows; elsewhere the check is skipped with a message). The check is free when even the largest possible table fits. Otherwise one small alignment of up to 200 genus representatives measures how many cross-genus pairs this reference set keeps, chosen without using random numbers so the build itself is unchanged, and the function stops if the prediction still does not fit, listing values of max_per_genus (for fetch_ncbi_reference_sequences(), which applies it to cached metadata without re-fetching) and max_seqs_per_taxon that would.

The result carries a size_calibration attribute recording the pairs the build could have produced and the pairs it kept. Pass the result to estimate_sequence_matrix_size()'s calibration to predict a similar reference set from measured rates rather than defaults.

### calibrate_query_noise(model_params, match_df, priors, plausibility_threshold = 0.001, min_confident_obs = 30L, offset_form = c("constant", "linear"), min_calib_species = 8L, calibrate_sigma = TRUE, min_sigma_obs = 100L, evidence_col = NULL, logit_epsilon = 1e-04, verbose = TRUE)

Calibrate a trained likelihood model to real query-vs-reference behavior

'train_likelihood_model()' estimates H1 (known-species) parameters entirely from reference-vs-reference pairs - two clean, curated database sequences compared to each other. That process cannot see technical noise specific to real queries (PCR error, sequencing error, degradation, ASV-inference artifacts), so a real, correctly-identified query routinely scores lower than the trained H1 mean predicts, and the "unreferenced" hypotheses (whose means sit further down the score axis, exactly where real queries land) can end up out-competing the correct referenced species.

| Param | Required | Default | Doc |
|---|---|---|---|
| model_params | yes |  | Object of class "taxa_model_params" from train_likelihood_model(). |
| match_df | yes |  | Data frame. Canonical match object for the same dataset model_params was trained for (e.g. match_obj_restored). Must contain observation_id, genus, and a score column. |
| priors | yes |  | Data frame. Occurrence-based priors for the same dataset (e.g. TaxaExpect output), with taxon_name, taxon_name_rank, and theta_mean. |
| plausibility_threshold | no | 0.001 | Numeric (default 1e-3). Passed to identify_confident_observations(). |
| min_confident_obs | no | 30L | Integer (default 30L). Minimum number of confident observations required to compute an offset. Below this, the function warns and returns model_params unchanged (offset = 0, sigma ratio = 1). |
| offset_form | no | c("constant", "linear") | Character (default "constant"). "constant" adds one additive offset to every H1 mean: the query scale is shifted to the reference scale by the amount the confident observations require, and the per-species locations keep their relative positions. "linear" instead remaps each H1 mean through intercept + slope * trained_mean, fit on per-species medians of the confident observations, so how much per-species structure transfers is estimated rather than assumed. The default is "constant" because it is the simplest correction to state and applies one method to every marker -- NOT because a held-out comparison selected it. The confident set such comparisons rest on is built by thresholding theta_mean, which is a SHARE of a pool denominator containing coarse-rank records, so it cannot adjudicate between the two forms; see Level-aware recalibration. The linear form's negative COI slope remains unexplained. "linear" falls back to "constant" (with a warning) when fewer than min_calib_species confident species, or no spread of trained means, are available. |
| min_calib_species | no | 8L | Integer (default 8L). Minimum number of distinct confident species (spanning a range of trained means) required to fit the offset_form = "linear" line. Ignored when offset_form = "constant". |
| calibrate_sigma | no | TRUE | Logical (default TRUE). Widen the H1 spread by the measured extra scatter of field queries over reference pairs: the ratio of the residual variance (5 percent trimmed each side) to the trained variance, never below 1. See the Sigma correction section. |
| min_sigma_obs | no | 100L | Integer (default 100L). Fewest confident observations from which the field scatter is measured. Below it the H1 spread is held at the conservative floor of 1.0 transform unit^2 (it is never narrowed where it cannot be checked); $Query_Calibration$sigma_source records which applied. |
| evidence_col | no | NULL | Character or NULL (default NULL). Name of a column in match_df giving each observation's raw evidence quantity (e.g. DNA read depth, image detection count, acoustic recording duration). When supplied, the median of this quantity across the confident observations is stored as reference_evidence in the returned $Query_Calibration slot -- the baseline evaluate_likelihoods()(evidence_col=) divides a query's own evidence quantity by, at inference time, to scale H1 sigma per-observation (more evidence than this baseline tightens sigma, less widens it -- unlike the rejected flat calibrate_sigma correction above, this is validated per-observation, not as one population-wide constant, based on the observed within-species correlation). Median chosen for the same robustness reason as the mean offset (a real, right-skewed depth distribution can span 5+ orders of magnitude). A global median across the whole confident set, not per-species/genus -- per-observation evidence quantity already carries the relevant signal regardless of species, and normalizing away a species' typical evidence level would reintroduce the same population-mismatch problem that broke the flat sigma correction. Calibration (this function, needs bulk confident-observation data) and inference (evaluate_likelihoods(), works on any number of observations, including one) are deliberately decoupled: once reference_evidence is baked into model_params here, scoring a single new observation later needs no recalibration. When NULL (default) or too few confident observations exist, reference_evidence is left NA -- evaluate_likelihoods() then applies no evidence-based adjustment at all, rather than guessing a baseline from insufficient data. |
| logit_epsilon | no | 1e-04 | Logit clipping value (default 1e-4), matching evaluate_likelihoods()'s own default. |
| verbose | no | TRUE | Logical (default TRUE). Print the estimated offset and how many confident observations/genera it was based on. |

**Value:** 'model_params', with 'H1_Global_Mu["score_logit"]' and 'H1_Lookup$mu_score' shifted by the estimated offset; 'H1_Sigma["score_logit", "score_logit"]' and every 'H1_Lookup$sigma_score' scaled by the estimated variance ratio (unless 'calibrate_sigma = FALSE'); and a new $Query_Calibration slot recording 'offset_logit', 'offset_form' (the form actually applied, which may be '"constant"' after a '"linear"' fallback), 'slope'/'intercept' (the applied mean remap: 'slope = 1', 'intercept = offset_logit' for the constant form), 'sigma_ratio', 'reference_evidence' ('NA' unless 'evidence_col' supplied), 'n_confident_obs', 'n_confident_genera', and 'plausibility_threshold' for auditability. Unchanged (with 'offset_logit = 0', 'offset_form = "constant"', 'slope = 1', 'intercept = 0', 'sigma_ratio = 1', 'reference_evidence = NA') if fewer than 'min_confident_obs' confident observations are found.

#### Details

This function estimates a single, marker-wide additive correction from observations where the true species can be identified with high confidence from independent, non-circular evidence -- occurrence/range priors, not the likelihood model's own scores -- via identify_confident_observations(). For each confident observation, the residual between its observed score_logit and its species' own trained mu_score (or the global mean, if that species has no H1_Lookup entry) is computed; the median residual across all confident observations is the calibration offset.

The offset is applied uniformly to H1_Global_Mu["score_logit"] and to every H1_Lookup$mu_score, shifting the absolute anchor of the model without altering the relative structure between species, or the H2/H3 congener-divergence deltas (which are differences from the shifted mean, so they carry through unchanged).

#### Sigma correction

train_likelihood_model() estimates the H1 spread from reference pairs. A field query is a reference-like sequence plus sequencing and amplification noise, so its scatter around a species' mean can only be wider. The correction measures that extra scatter on the confident observations (variance of their residuals, 5 percent trimmed each side, over the trained variance) and widens the spread by it; it never narrows. The variance is used because identity scores on a short amplicon take few distinct values, on which a median absolute deviation can collapse to zero and narrow the spread. With fewer than min_sigma_obs confident observations the scatter cannot be measured, and the spread is held at the conservative floor of 1.0 transform unit^2.

#### Level-aware recalibration (offset_form = "linear")

The default "constant" form is correct only if the train-vs-inference scale gap is a pure location shift -- the same additive offset for every species, regardless of identity level. A single additive offset cannot check that assumption, and it can fail: when scores come from a different instrument or pipeline than the reference-vs-reference alignment, the per-species H1 means estimated from build_sequence_matrix() may not transfer to the inference scale at all. Regressing each confident species' required offset on its trained mean then gives a slope near -1 (real correct-species query scores collapse toward one identity level regardless of the reference alignment's self-similarity), and a single pooled inference-scale mean predicts confident queries better than "per-species trained mean + one offset".

offset_form = "linear" addresses this by remapping every H1 mean through a robustly-fit line intercept + slope * trained_mean (fit on per-species medians, weighted by observation count) instead of adding one constant. It is a strict generalization: slope = 1, intercept = offset reproduces the constant form exactly, so it degrades to "constant offset" when the per-species structure does transfer (slope -> 1) and to "one pooled inference location for all species" when it does not (slope -> 0). The slope is NOT constrained to [0, 1]: a negative slope means the observed query score falls as the trained mean rises, so the remap reverses the order of the species' expected scores; a slope above 1 stretches it. Inspect $Query_Calibration$slope rather than assuming it lies in [0, 1]. Only the H1 mean location is remapped; the H2/H3 congener-divergence deltas (defined relative to the H1 mean) and the gap feature -- the structure that actually discriminates between candidate species -- are untouched. "linear" requires at least min_calib_species confident species spanning a range of trained means; it falls back to "constant" with a warning otherwise.

Two caveats bear on choosing between the forms. First, the confident set is selection-biased toward abundant, well-sampled, easy genera and has, by construction, exactly one plausible species per genus, so it can measure absolute H1 location fit but cannot directly test congener discrimination: a "linear" fit whose slope collapses to 0 removes per-species location structure that is not real on the inference scale, but this validation set cannot confirm that removal is safe in hard congener-vs-congener cases. Second, the confident set is built by thresholding theta_mean, a SHARE of a pool denominator that includes coarse-rank records (rows naming no species), so every species' value is diluted and the set contains observations that are not truly confident. The set therefore cannot adjudicate between the two forms. "constant" is the default because it is the SIMPLEST correction to state and applies one method to every marker -- a stated default, not a measured winner. "linear" is available when a marker's own evidence supports a slope.

The linear form is a post-hoc calibration against an independent, non-circular anchor set, analogous in spirit to Platt scaling for classifier outputs (Platt 1999) but linear-in-the-location rather than logistic, and it addresses a train-vs-inference dataset shift (Quinonero-Candela et al. 2009) that arises because percent identity is an operationally-defined quantity whose value for a fixed pair of sequences depends on the alignment method and denominator (May 2004; Raghava & Barton 2006). See inst/TaxaLikely_supplemental_methods.md Section 11A for the derivation, the empirical result, and references.

#### Scope

This estimates one offset for the whole model (i.e., one marker/dataset), not a per-species correction -- there usually isn't enough confident-genus coverage to support anything finer, and the confident set can never contain cross-species information anyway. Do not reuse an offset estimated on one marker (or one primer set) for another: the size of this gap varies by roughly an order of magnitude between markers of different length and quality and does not transfer as either a fixed percentage or a fixed mismatch count. The same applies across score_transform values: the offset is estimated on whichever scale model_params$Score_Transform says the model was trained on (read automatically), but a "logit"-scale offset and a "sqrt_mismatch"-scale offset are different numbers in different units -- never reuse one for the other, and always recompute after retraining with a different score_transform.

#### Bimodality diagnostic

train_likelihood_model() fits ONE Gaussian per species for H1, and this function's offset_form = "linear" fits a single line across species -- both assume the underlying H1 score distribution is unimodal. Mixing sequencing platforms (or markers, or primer sets) inside one calibration run breaks that assumption silently (e.g. a Nanopore top-hit distribution with a spike at exactly 100 and a long lower tail, against tight, unimodal Illumina data for the same marker), and fitting one Gaussian or one line across such a mix lands the mean between the two modes, where almost nothing actually is.

This function therefore runs an internal two-component-normal-mixture-vs-BIC check (see .bimodality_check()) on the SAME confident-observation score vector (p_norm * 100, i.e. raw percent identity, computed before the score_transform step) that the calibration itself fits. The check flags bimodality only when a 2-component fit beats a 1-component fit by delta_bic > 10 (Kass & Raftery 1995's "very strong" evidence band; see .bimodality_check() for the citation) AND the two fitted component means are separated by more than 1 percentage point (or further, on discrete data -- see the next section) AND the fitted mixture has a genuine density dip between the two means AND the smaller component holds real mass. All four guard against a false positive from ordinary, ceiling-skewed but unimodal H1 data; a simpler skewness/kurtosis-based bimodality-coefficient test would flag that shape on its own, because H1 scores pile up near 100% identity by construction.

#### Percent identity is discrete, not continuous

Percent identity on a short, fixed-length amplicon is DISCRETE: a ~167bp amplicon can only take values spaced by roughly one mismatch's worth of identity (about 0.6). Real match-score data therefore forms a "comb" of spikes at each mismatch count, not a continuum, and a comb has LITERAL zero density in the gaps between teeth -- quantization, not a valley between two populations. A two-component Gaussian mixture always beats one component on comb-like data (a delta_bic in the thousands), and the density-dip guard passes on a comb because a dip genuinely sits between the teeth.

.bimodality_check() therefore (1) estimates the identity-per-mismatch quantum directly from the data (NA when the data don't look comb-shaped at all; most continuous data, including a genuine platform mixture, estimates no quantum and is checked without smoothing); (2) when a quantum is found, deterministically smooths the comb before fitting (spreading each tied group of observations evenly across its own quantum-wide cell, a dependency-free continuity correction that closes the zero-density gaps without disturbing a real multi-quantum gap between two separate populations); (3) requires the minority component to hold real mass (>= 15%) before calling it a mode, since a thin tail is not a second population; and (4) requires the two fitted means to be separated by more than a few QUANTA, not just the flat 1.0 percentage point, which is under two mismatches on a 167bp amplicon. See .estimate_score_quantum(), .smooth_comb(), and .bimodality_check() for the mechanism and exact thresholds.

When the check fires, this function emits exactly ONE warning() naming the fitted structure in plain numbers (component weights, means, sds, and delta_bic) and pointing at the remedy -- calibrating mixed platforms or markers separately, which this function does NOT do for you. This is a diagnostic only: it never changes any fitted value (the offset, offset_form, slope/intercept, or sigma ratio) and calibration is never refused. train_likelihood_model() runs the identical check on its own H1 training scores and RECORDS the result in Stats$h1_bimodality without warning; the warning belongs here, where a single, possibly wrong, offset/line is actually applied to inference-time scores.

### check_cross_genus_sampling_noise(reference_df, rank_system = NULL, max_dist = 0.25, min_seq_len = 100L, max_seq_len = 2000L, filter_unnamed = TRUE, max_seqs_per_taxon = NULL, barcode_term = NULL, max_foreign_reps_per_genus = 20L, n_replicates = 5L)

How Much Does the Random Cross-Genus Draw Move the Estimate?

'build_sequence_matrix(by_genus = TRUE)' represents each genus by ONE randomly-drawn sequence when building the cross-genus sample that feeds H3 (and H2's pooled fallback). This re-runs that whole draw-and-align step 'n_replicates' times and reports how much the resulting cross-genus pair distribution moves across replicates - a transparency report, like 'TaxaExpect::kernel_budget_sensitivity()''s own per-group budget table, not a pass/fail gate. There is no universal "good enough" spread to check against; the point is to make the spread visible so you can judge whether it is small ...

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| rank_system | no | NULL | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| max_dist | no | 0.25 | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| min_seq_len | no | 100L | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| max_seq_len | no | 2000L | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| filter_unnamed | no | TRUE | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| max_seqs_per_taxon | no | NULL | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| barcode_term | no | NULL | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| max_foreign_reps_per_genus | no | 20L | Forwarded to build_sequence_matrix(by_genus = TRUE, ...), identically for every replicate. |
| n_replicates | no | 5L | Integer (default 5L). How many independent random representative draws to compare. Each draw consumes the caller's RNG state (sample(), same convention as max_seqs_per_taxon) -- do NOT call set.seed() between replicates, and do NOT pass build_sequence_matrix(seed =) through, or every "replicate" would be identical and this function would report zero noise. |

**Value:** A list: 'replicates' Data frame, one row per replicate: 'replicate', 'n_cross_genus_pairs' (the count of DISTINCT unordered cross-genus sequence pairs - '.decipher_align_pairs()''s underlying pair table carries both (i, j) and (j, i) for every pair, and this count de-duplicates that before reporting), 'mean_p_match', 'median_p_match', 'sd_p_match'. 'summary' Named list: the range (min, max) and coefficient of variation (sd/mean) of 'mean_p_match' across replicates - the single number worth looking at first.

#### Cost

Each replicate re-runs the FULL by_genus = TRUE pipeline (including the within-genus alignments, not just the cheap cross-genus step) -- simpler and safer than threading a special reduced-recompute path through build_sequence_matrix()'s internals, at the cost of some real redundant work. Because by_genus = TRUE already made the whole pipeline substantially cheaper than one whole-set alignment (see build_sequence_matrix()'s own @section Per-genus alignment), n_replicates repeats of it can still cost meaningfully LESS than a single whole-set run would have -- but this is still real, additive NCBI-free compute cost, not free; run it once when adopting by_genus = TRUE for a new marker, not on every training run.

### compute_rank_thresholds(seq_matrix, rank_system = NULL, prior_weight = 10, threshold_grid = seq(0, 100, by = 1))

Derive marker-specific rank_thresholds via per-rank Youden's J

A real, exported, marker-agnostic version of the 'score_floor_roc_sweep.R' diagnostic (TaxaID_dev repository)'s per-rank Youden's J logic: given a 'build_sequence_matrix()'-style pairwise distance matrix for YOUR marker and reference database, returns the percent-identity threshold at each taxonomic rank (species/genus/family) that maximizes true-positive minus false-positive rate for that rank's own, correctly-matched positive/ negative classes - species tier: TP = within-species, FP = congeneric; genus tier: TP = same-genus, FP = confamilial; family tier: TP = same-family, FP = ...

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_matrix | yes |  | Data frame of pairwise match scores, as returned by build_sequence_matrix(), for the SAME marker/reference database score_consensus() will be scoring against. Every pair must have known taxonomy on both sides (species/genus/family), which is exactly what build_sequence_matrix() already produces. |
| rank_system | no | NULL | Character vector of rank names, coarse to fine, e.g. c("family", "genus", "species"). Default NULL auto-detects from .x-suffixed columns in seq_matrix (same convention as train_likelihood_model()). |
| prior_weight | no | 10 | Numeric. Empirical Bayes shrinkage weight for the per-genus/per-family curves (default 10.0, matching train_likelihood_model()'s own default). |
| threshold_grid | no | seq(0, 100, by = 1) | Numeric vector of percent-identity thresholds to search over. Default seq(0, 100, by = 1). |

**Value:** A named numeric vector, a subset of 'c(species=, genus=, family=)' depending on what 'rank_system'/'seq_matrix' make computable - directly usable as 'TaxaAssign::score_consensus(rank_thresholds = ...)'. Errors if nothing is computable at all (fewer than 2 usable rank levels).

#### Details

Exists specifically because TaxaAssign::score_consensus()'s rank_thresholds has no safe universal default (see that function's own documentation) -- this is the "derive your own from real reference data" option that error message points at.

### detect_suppressed_candidates(match_obj, score_col = "score_original", observation_id_col = "observation_id", perfect_threshold = 100, purity_threshold = 0.99, singleton_threshold = 0.98)

Detect pipeline rules that suppress candidate rows in a match object

Inspects a match object for evidence that an upstream tool suppressed lower-scoring candidates. Three patterns are recognised:

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. Standardised match object containing at least observation_id_col. score_col is optional; Rules 1 and 2 are skipped when it is absent. |
| score_col | no | "score_original" | Character. Name of the score column (default "score_original"). |
| observation_id_col | no | "observation_id" | Character. Name of the observation ID column (default "observation_id"). |
| perfect_threshold | no | 100 | Numeric. Score at or above which a candidate is considered a "perfect" match for Rule 1 detection (default 100). Set to 95 for pipelines that enforce a 95-percent identity floor, for example. |
| purity_threshold | no | 0.99 | Numeric in (0, 1]. Fraction of qualifying observations that must exhibit the pattern for the rule to be flagged (default 0.99). A high value reduces false positives from rounding artefacts. |
| singleton_threshold | no | 0.98 | Numeric in (0, 1]. Fraction of all observations that must be singletons (1 row) for Rule 3 to be flagged (default 0.98). |

**Value:** A named list: 'rule_detected' Logical. 'TRUE' if any rule is flagged. 'rules' Character vector of flagged rule names (may be empty). 'perfect_only' Logical. 'max_score_ties' Logical. 'best_only' Logical. 'has_score_col' Logical. Whether 'score_col' was found. 'n_total' Integer. Unique observations. 'n_perfect_obs' Integer. Observations with >=1 score >= 'perfect_threshold'. 'purity_perfect' Numeric. Fraction of perfect-obs that are pure (no sub-threshold rows). 'n_multi_obs' Integer. Observations with >1 row. 'purity_ties' Numeric. Fraction of multi-row obs with uniform scores. 'frac_singleton' Numeric. Fraction of obs that are singletons. 'example_observations' Character. Up to 5 affected observation IDs.

#### Details

- "perfect_only": Among observations where at least one candidate scores at or above perfect_threshold, none also contains a row below that threshold. Typical cause: a 100-percent rule that drops all sub-perfect hits when a perfect match exists.

- "max_score_ties": Multi-row observations show zero within- observation score variance -only tied-top candidates were returned.

- "best_only": Essentially all observations have exactly one candidate row, indicating a top-1 pipeline, pre-computed consensus, or absence of a score column.

Detection is conservative: a rule is flagged only when the observed pattern is present in at least purity_threshold of qualifying observations.

### estimate_sequence_matrix_size(x, max_per_species = c(NA, 20, 10), max_per_genus = c(NA, 1000, 500, 250), max_seqs_per_taxon = NULL, by_genus = TRUE, max_foreign_reps_per_genus = 20L, n_ranks = 3L, calibration = NULL, memory_budget_fraction = 0.7, available_gb = NULL)

Predict the memory a sequence matrix will need, for a grid of caps

'build_sequence_matrix()' returns one row per ordered pair of reference sequences within 'max_dist', and 'train_likelihood_model()' holds several working copies of that table. On a broad reference set this table is what exhausts memory, and its size is fixed by the genus and species composition of the reference set, which is known before anything is aligned. This function predicts it for each combination of 'max_per_species' and 'max_per_genus', so a cap can be chosen from numbers rather than found by a failed run.

| Param | Required | Default | Doc |
|---|---|---|---|
| x | yes |  | The reference set: a data frame with genus and species columns and one row per sequence (a reference_df, or the sequences element of a fetch_ncbi_reference_sequences() dry run), or one row per species with an integer count column n. With an accession column (acc, acc_version or composite_id) the caps choose the same rows the fetch would; without one, species_dropped shows what a cap of that size drops from a set of this shape, not the exact species. |
| max_per_species | no | c(NA, 20, 10) | Numeric vectors of the caps to compare, as in fetch_ncbi_reference_sequences(); NA means no cap. Every combination is evaluated. |
| max_per_genus | no | c(NA, 1000, 500, 250) | Numeric vectors of the caps to compare, as in fetch_ncbi_reference_sequences(); NA means no cap. Every combination is evaluated. |
| max_seqs_per_taxon | no | NULL | The values that will be passed to build_sequence_matrix(). max_seqs_per_taxon is applied after the fetch caps, as the build applies it. |
| by_genus | no | TRUE | The values that will be passed to build_sequence_matrix(). max_seqs_per_taxon is applied after the fetch caps, as the build applies it. |
| max_foreign_reps_per_genus | no | 20L | The values that will be passed to build_sequence_matrix(). max_seqs_per_taxon is applied after the fetch caps, as the build applies it. |
| n_ranks | no | 3L | Number of rank columns the matrix will carry (the length of rank_system); each adds 16 bytes per pair. |
| calibration | no | NULL | Optional: a build_sequence_matrix() result, its size_calibration attribute, or a list of either, from a reference set of similar breadth. Its measured retention rates replace the defaults in pairs_predicted. |
| memory_budget_fraction | no | 0.7 | Fraction of available memory counted as usable (default 0.7). |
| available_gb | no | NULL | Available memory in GB. NULL (default) reads it from the operating system (macOS, Linux and Windows); NA when it cannot be read, and then fits is NA. |

**Value:** A list: 'grid' One row per cap combination: 'max_per_species', 'max_per_genus', 'n_sequences', 'n_genera', 'n_species', 'n_species_dropped', 'largest_genus', 'pairs_predicted', 'pairs_ceiling', 'gb_matrix', 'gb_peak', 'gb_peak_ceiling', and 'fits' (whether 'gb_peak' is within the budget). 'species_dropped' A list parallel to 'grid''s rows: the species each combination removes entirely. 'available_gb', 'budget_gb' The memory the verdict used. 'rates' The retention rates used, and where they came from.

#### How memory scales

With by_genus = TRUE the pairs, before the distance filter, are sum_g n_g(n_g - 1) + 2 f sum_g (n_g - 1) + G(G - 1) for n_g sequences in genus g, G genera and f = \min(max_foreign_reps_per_genus, G - 1): within-genus pairs, each sequence against its genus's foreign representatives, and the representatives against each other, all counted in both directions. Two things follow. Memory grows with the square of the sequences in the largest genera, which is what max_per_species and max_per_genus control. It also grows with the square of the number of genera, which no cap controls: at 11,000 genera the representative term alone is 121 million pairs before filtering. Only a narrower taxon list reduces that term.

Use max_per_species first. It never removes a species, and a species with thousands of sequences (a model organism, a pest, a fishery species) is usually where the bloat is. max_per_genus second: it samples across the whole genus, so in a genus with more species than the cap allows, whole species are dropped. The species_dropped element of the result names them.

#### How accurate the prediction is

The pair structure above is exact. What is estimated is the fraction of those pairs the distance filter keeps. Within a genus it was 0.942 on COI and 0.551 on a 12S set fetched under the bare "12S" window (plausibly because congeners' sequences there cover different stretches of the gene). Across genera it depends on how broad the reference set is: 0.313 on a COI set spanning the animal kingdom and 0.348 on the 12S set; a set drawn from one family should keep more. Without calibration, pairs_predicted uses the COI rates, which fit a broad reference set; pairs_ceiling assumes every pair is kept and cannot be exceeded. For a narrow reference set read the ceiling, or calibrate. build_sequence_matrix() does not rely on these defaults: before aligning, it measures the cross-genus rate on the actual sequences. Pass an earlier build of a similar reference set as calibration to use its measured rates instead; each build_sequence_matrix() result carries them. Against a real 11,322-genus COI build of 110.3 million pairs, rates measured on 4,500 genera sampled independently of it predicted 112.9 million (2% high); single samples of 300 genera were within 7%.

The peak through training (the table plus the working copies train_likelihood_model() makes, together about peak_multiple times the table plus 0.3 GB) is R's own memory, measured with gc() on real COI builds. The operating system can report less, because macOS compresses idle memory; a run can therefore survive a gb_peak above the memory available, slowly and on compressed memory, but not above R's own vector limit. Treat gb_peak as a guide to the right order of magnitude with a margin, not as a guarantee: other objects in the session also need memory, which is why only memory_budget_fraction of the available memory is counted as usable.

### evaluate_likelihoods(match_df, model_params, rank_system = NULL, ratio_threshold = 0.01, min_match_threshold = 0.5, alpha = 0.001, n_sims = 0L, score_bounds = NULL, logit_epsilon = 1e-04, max_gap_ceiling = NULL, min_coverage = NULL, evidence_col = NULL, evidence_max_ratio = 1, verbose = FALSE)

Convert match scores to likelihoods for all queries

Applies the trained likelihood model to every 'observation_id' in the match object and returns a tidy data frame suitable for input to 'TaxaAssign::compute_posterior()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame in the canonical match-object format (output of TaxaMatch::standardize_match_data() or user-supplied). Must contain observation_id, score_original (or p_match or score), taxon_name, taxon_name_rank, and taxonomy columns matching rank_system. |
| model_params | yes |  | Object of class "taxa_model_params" from train_likelihood_model(). The scale H1/H2/H3 were trained on (model_params$Score_Transform, "logit" or "sqrt_mismatch") is read automatically -- callers do not supply or track it separately. evidence_col/min_coverage work identically regardless of Score_Transform: their SE(transform(score)) propto 1/sqrt(N) justification holds (with a different, p-dependent proportionality constant) for either scale, confirmed via the delta method. |
| rank_system | no | NULL | Character vector of rank names coarse to fine (e.g., c("family", "genus", "species")). Default NULL auto-detects from columns in match_df. |
| ratio_threshold | no | 0.01 | Minimum likelihood ratio to retain a specific candidate (default 0.01). Specific candidates with likelihood ratio less than 1% of the best hypothesis are dropped; the generic unreferenced_species/unreferenced_genus rows are always retained, because their prior can make them competitive on the posterior even when their likelihood is small. This removes noise hypotheses that would not meaningfully affect posterior probabilities. Note: the per-species sigma floor (see Details) ensures that well-sampled species with artificially tight training distributions still clear this threshold at realistic query scores, so the default 0.01 is appropriate for most sequence/image/acoustic workflows. |
| min_match_threshold | no | 0.5 | Minimum raw score to consider a candidate (default 0.50). Queries whose best candidate scores below 50% identity are considered unmatchable and routed to the $unresolved output for re-evaluation with a coarser rank_system. |
| alpha | no | 0.001 | Mahalanobis p-value cutoff for outlier rejection (default 0.001). See .evaluate_one_query() for full description. |
| n_sims | no | 0L | Monte Carlo simulations per query (default 0 = point estimate only). |
| score_bounds | no | NULL | Optional c(min, max) for score normalization. |
| logit_epsilon | no | 1e-04 | Logit clipping value (default 1e-4). |
| max_gap_ceiling | no | NULL | Gap cap (default 5.0). Caps gap at 5 logit units (roughly the gap between 99.3% and 50% identity) to prevent extreme outliers from dominating model estimates. |
| min_coverage | no | NULL | Numeric or NULL (default NULL). When not NULL and the match object contains a coverage column (e.g., BLAST qcovs divided by 100, or bounding-box area from TaxaMatch::read_animl_output(bbox_cols=)), candidate rows below this threshold are dropped before per-taxon score aggregation. A coverage column can be added to any match object via the coverage_col parameter of TaxaMatch::standardize_match_data(). Typical values: 0.8 (80% query coverage) for DNA BLAST results. NA coverage values are always retained (treated as fully covered). When coverage is absent from match_df, this parameter is silently ignored. Every candidate below threshold: when min_coverage drops EVERY candidate row for a given observation_id, that observation is routed to $unresolved (with a named warning) instead of erroring -- the same degrade-gracefully convention already used for the coarser-than-rank_system case above. Confirmed to hit 195/800 (24.4%) of real test queries in a real production A/B comparison at a Youden's-J-calibrated min_coverage. Re-run evaluate_likelihoods() on $unresolved with a lower (or NULL) min_coverage to resolve these queries. |
| evidence_col | no | NULL | Character or NULL (default NULL). Name of a column in match_df giving each candidate's raw evidence quantity (e.g. DNA read depth, image detection count, acoustic recording duration -- whatever is appropriate for the data type). When supplied, H1 sigma is rescaled by a factor 1/sqrt(evidence_ratio), where evidence_ratio is this quantity divided by model_params$Query_Calibration$reference_evidence -- a baseline set once, in bulk, by calibrate_query_noise()(evidence_col=). Unlike min_coverage/coverage inflation above, this is symmetric: an observation with more evidence than the baseline tightens sigma, not just widens it for less. The rescale is only ever applied when doing so is provably non-decreasing for the density at the query's own (pre-rescale) standardized distance from the species mean -- see @section Evidence-based sigma rescaling below for the exact criterion and why it replaced an earlier unconditional version. Produces score_likelihood_evidence, a parallel point-estimate column (no Monte Carlo variant, matching score_likelihood_cov's own precedent) -- identical to score_likelihood when evidence_col is absent, not present in a given candidate row, the model was never calibrated with a reference_evidence baseline, or the gate criterion below isn't met; never guessed. Works identically for a single-observation match_df as for a large batch, since the baseline is read from model_params, not re-derived from match_df itself. |
| evidence_max_ratio | no | 1 | Numeric (default 1). Caps how much evidence_ratio may tighten sigma (values above this are clipped to it before the 1/sqrt() scaling); widening for evidence_ratio < 1 is never capped. Default 1 means evidence never tightens sigma at all, only widens -- found necessary empirically: an uncapped ratio crashed a real, correctly-identified, high-depth observation's H1 likelihood to exactly 0 (its score wasn't precisely at the trained mean, and real variability doesn't vanish just because evidence is abundant). Raise above 1 only after validating on your own data -- the gate described in @section Evidence-based sigma rescaling protects the tightening direction using the same criterion as widening, but has not itself been validated against real over-tightening cases the way the widen-only default has been. |
| verbose | no | FALSE | Logical (default FALSE). When TRUE, prints a message each time a species falls back to global parameters (no species-specific lookup entry found). |

**Value:** A named list with two components: $likelihoods Data frame with one row per 'observation_id' x taxon hypothesis, suitable for input to 'TaxaAssign::compute_posterior()': 'observation_id', 'taxon_name', 'taxon_name_rank', 'hypothesis_type' ('"specific_candidate"', '"unreferenced_species"', or '"unreferenced_genus"'), 'raw_likelihood', 'raw_likelihood_cov', 'raw_likelihood_evidence' (the bivariate-normal density - 'mvtnorm::dmvnorm()' over (score_logit, gap_logit) jointly - BEFORE ratio-normalization against the best candidate in the same observation; 'score_likelihood' etc. below are each 'raw_likelihood / max(raw_likelihood)' within that observation. Because 'score_likelihood' is always exactly 1.0 for a candidate with no real competitor, it cannot say whether a "winning" match is actually a good absolute fit - 'raw_likelihood' can, and is comparable across observations within one trained model/marker in a way the ratio never was; not calibration-free in an absolute sense (still evaluated against 'H1_Lookup''s calibrated or uncalibrated mu/sigma), but a within-marker relative comparison such as "above or below this marker's own median" sidesteps that), 'score_likelihood', 'score_likelihood_mean', 'score_likelihood_sd', 'score_likelihood_cov', 'score_likelihood_evidence', 'h2_delta_source' ('"genus_specific"' or '"global_fallback"' for 'unreferenced_species'/'unreferenced_genus' rows; 'NA' for 'specific_candidate' rows), plus the *_confusion_risk columns described under *Confusion risk* below. $unresolved Rows from 'match_df' for any 'observation_id' that produced no usable likelihoods (empty data frame if none). Pass to a second call of 'evaluate_likelihoods()' with a coarser 'rank_system' to recover these queries.

#### Details

For each query the function:

- Groups candidates by taxon_name and takes the median score across references (robust to outlier accessions and sample-size bias).

- Logit-transforms and computes the gap relative to the runner-up taxon.

- Looks up species-specific parameters from the model (with hierarchical fallback to genus, then global mean).

- Evaluates H1/H2/H3 likelihoods and normalises to ratios.

Three hypotheses: For each query, three types of hypothesis are evaluated:

- H1 (specific_candidate): The query comes from a known species in the reference database. The model predicts what a true match to this species looks like based on reference-vs-reference scores.

- H2 (unreferenced_species): The query comes from a species not in the reference database, but whose genus is represented. The model shifts the H1 score distribution downward (by H2$delta logit units, or by a genus-specific shrunk delta from model_params$H2_Lookup when the anchor candidate's genus has real congener data -- see h2_delta_source below) to predict what a sister-species match looks like.

- H3 (unreferenced_genus): The query comes from a genus not in the reference database at all. The score distribution is shifted further downward (by H3$delta).

Features:

- score_logit: The raw match score (e.g., percent identity), normalised to 0-1 and logit-transformed. The logit maps the bounded score onto the real line, allowing Gaussian modelling.

- gap_logit: The difference between the best within-taxon logit score and the best cross-taxon logit score. A large gap means the top candidate is much better than any alternative -- strong evidence for that identification. When only one candidate taxon exists, the gap is not computed (1D model used instead).

Per-species sigma floor: When a species is found in H1_Lookup, its per-species sigma_score (score variance) is used in place of the global H1_Sigma[1,1]. The per-species estimate can be artificially small for well-sampled species whose reference sequences are nearly identical (many accessions from the same voucher or population); such a tight distribution would reject realistic query scores of any kind (sequence, image, or acoustic) that fall slightly below the near-perfect reference mean, giving the species a near-zero H1 likelihood so that ratio_threshold silently drops it. To prevent this, evaluate_likelihoods() floors the per-species sigma at the global H1_Sigma[1,1]: species-specific sigma is used only when it is larger than global. This has negligible impact on discrimination between closely related species because the global sigma (SD \approx \sqrt{H1\_Sigma[1,1]}) still spans the logit range corresponding to a few percent identity difference.

Coverage-adjusted likelihood (score_likelihood_cov): When the match object contains a coverage column (e.g., BLAST qcovs / 100 or bounding-box area), a parallel point estimate score_likelihood_cov is computed alongside score_likelihood. For each specific candidate, the H1 sigma_score is widened by 1 / \sqrt{\text{coverage}} before evaluating the likelihood -- grounded in binomial sampling theory where SE(\text{logit}(\hat{p})) \propto 1 / \sqrt{N_{\text{aligned}}} and N_{\text{aligned}} = \text{coverage} \times N_{\text{total}}. H2 and H3 sigmas are global fixed parameters and are not inflated. When coverage is absent or equals 1 for all candidates, score_likelihood_cov is identical to score_likelihood. Pass to TaxaAssign::compute_posterior() instead of score_likelihood to apply the coverage adjustment; compare the two columns to identify queries where coverage meaningfully shifts the likelihood ratios.

Evidence-based sigma rescaling (score_likelihood_evidence) and its crossover gate: Rescaling every candidate's H1 sigma_score whenever evidence_ratio < 1 (widening for low-evidence candidates, like the coverage adjustment above) is net negative, even capped at evidence_max_ratio = 1. A Gaussian must integrate to 1, so widening its variance lowers its peak while raising its tails. For a variance rescaled by a factor c (c > 1 widens, c < 1 tightens), the log-density at a point z standard deviations from the species mean changes by exactly: \Delta = -\tfrac{1}{2}\log(c) + \tfrac{1}{2}z^2\left(1 - \tfrac{1}{c}\right) which is non-negative only when z is large enough (for widening) or small enough (for tightening) that the tail/peak tradeoff pays for itself. Most low-evidence observations are still decent, close-to-mean matches (small z), so unconditional widening pays the peak-lowering cost far more often than it collects the tail-raising benefit. evaluate_likelihoods() therefore computes \Delta directly (using z standardized against whatever sigma is already in effect after the per-species floor and coverage inflation) and applies the evidence rescale only when \Delta > 0, i.e. only where it cannot lower the candidate's H1 density relative to leaving sigma untouched. This is an exact, closed-form condition, not a heuristic threshold, and it degrades to a no-op as evidence_ratio approaches 1. One caveat for multi-candidate queries: the gate uses the score-only marginal z, not the exact bivariate (score_logit, gap_logit) crossover (only sigma_score is rescaled; the gap variance and score/gap covariance are untouched, so the true joint crossover also depends on the correlation term), consistent with the score-only outlier test described above. Candidates sitting right at the gate's decision boundary can therefore see a small decrease in H1 density. For singleton (1D) queries the gate is exact.

Genus-specific H2/H3 delta (h2_delta_source): H2$delta/H3$delta are single values pooled across every genus seen during training. When train_likelihood_model() found at least one real congener pair for the query's best-matching candidate's genus, evaluate_likelihoods() instead uses a genus-specific delta (model_params$H2_Lookup, shrunk toward the pooled value by how many congener pairs were available) and marks the row h2_delta_source = "genus_specific". Rows marked "global_fallback" (including every row when the genus has only one referenced species, or when the model was trained without genus information) used the pooled constant, the cruder approximation -- treat unreferenced_species/unreferenced_genus likelihoods on those rows with more caution. This correction only adjusts the shift's magnitude for the correct genus; it does not address the case where the true taxon's nearest relative in evidence space (visual or acoustic mimicry/convergence) is not its nearest phylogenetic relative -- see inst/TaxaLikely_supplemental_methods.md.

H2/H3 mean anchor and genus-specific variance: H2's mean is (anchor candidate's own resolved species mean) - delta, not H1_Global_Mu - delta: a referenced species whose own trained mean sits above or below the population average is real information about how conserved or variable that lineage is, and an unreferenced sister species should inherit it. When a genus-specific H2_Lookup entry exists, its own shrunk congener variance (var_shrunk) is used for H2's sigma in place of the pooled global value, since genera whose species are hard to tell apart (small delta) also tend to show more consistent divergence (lower variance); otherwise both fall back to the pooled global values. See train_likelihood_model()'s score_transform documentation for why this requires "sqrt_mismatch" rather than the plain logit scale to be correctly signed.

Monte Carlo uncertainty (score_likelihood_mean/score_likelihood_sd): Represents uncertainty in the likelihood estimate itself, driven by how much reference data calibrated the trained mean being evaluated (H1_Lookup$n_obs_species for a specific candidate; H2_Lookup$n_pairs for a genus-specific H2/H3 delta, or Stats$n_h2_pooled when no genus-specific delta exists), not by resampling the query's own observed score. Each of the n_sims draws perturbs the candidate's trained mean by its own estimation uncertainty (Var(mean) ~= sigma^2/n) and evaluates the query's real, fixed observed point against that draw. Practical consequence: a poorly-referenced species gets a wider score_likelihood_sd than a well-referenced one for the identical observed score, and unreferenced_species/unreferenced_genus rows -- which borrow a shifted mean rather than being directly observed -- are systematically wider than specific_candidate rows. The draws reuse whichever per-candidate sigma the evidence-adjusted point estimate already resolved (species floor + evidence gate, when applicable), so a low-depth candidate's evidence-widened sigma also widens its mean uncertainty. Falls back to a score-resampling approach when model_params$H1_Lookup is empty or absent (no species-level training data).

#### Confusion risk

species_confusion_risk/genus_confusion_risk/family_confusion_risk are a score-only, model-free diagnostic, not a second application of this function's trained bivariate-normal likelihood. Each answers, at its own rank: given this row's raw match score and its own genus (for species_confusion_risk) or family (for genus_confusion_risk), how often would a REAL congener/confamilial pair score this high or higher in the training reference database? They are read off model_params$Confusion_Risk_Curves (genus-/family-equal-weighted, Empirical-Bayes-shrunk curves computed once by train_likelihood_model(); see its Confusion_Risk_Curves documentation and the score_floor_roc_sweep.R diagnostic, TaxaID_dev repository, from which the curves are built).

Higher means MORE confusable, i.e. WEAKER evidence for the rank in question, matching the high=concern convention of risk-style metrics (e.g. TaxaFlag::flag_contaminant()'s contaminant_score), not the higher-is-better convention of score_likelihood/posterior_mean/ confidence_score. These are one-sided tail probabilities (p-value-like for the null "this is just a confusable relative"): species_confusion_risk = 0.97 means a real congener would score this high 97% of the time too (weak evidence the species call is correct), while 0.02 means a real congener almost never scores this high (strong evidence). family_confusion_risk has no grouping variable (a single, ungrouped cross-family rate) since no rank exists above family to equal-weight by. own_rank_confusion_risk points at whichever of the three matches this row's hypothesis_type (species_confusion_risk for specific_candidate, genus_confusion_risk for unreferenced_species, family_confusion_risk for unreferenced_genus), but all three are populated for every row (where computable), so a reviewer can also see e.g. "resolved to species, but genus_confusion_risk is also high."

Purely informational: never zeroes a likelihood or changes which hypothesis wins. NA when model_params$Confusion_Risk_Curves lacks the relevant tier (e.g. rank_system too short) or this row's own genus/family is unresolved (e.g. unreferenced_genus rows have no genus, so species_confusion_risk is always NA there). See TaxaAssign::posterior_consensus()'s winner_*_confusion_risk and winner_own_rank_confusion_risk pass-through for how a downstream consumer reads these off the winning row.

#### Pair-coverage check

On every call, .check_pair_coverage_floor() compares match_df's own alignment-coverage floor against model_params$Stats$min_pair_coverage (the floor train_likelihood_model(min_pair_coverage=) was trained under). It reads attr(match_df, "report_params")$min_query_coverage when present (set by TaxaMatch::blast_sequences()), else falls back to the observed minimum of match_df$query_coverage; a value greater than 1 is treated as a 0-100 percentage and normalised to 0-1. It warns only when the match object's floor sits more than 0.01 below the model's own min_pair_coverage, i.e. when inference is asked to evaluate the gap feature on lower-coverage hits than the model was trained on. The check is one-directional: a match object with a STRICTER coverage floor than training never warns. It is silently skipped when model_params was trained with no coverage floor, or when neither report_params nor a query_coverage column is available on match_df.

### expand_unreferenced_hypotheses(likelihood_df, unreferenced_df)

Expand unreferenced hypotheses from genus/family level to named species

This is the value-modeling half of unreferenced-taxon handling ("borrow a likelihood from referenced relatives"), which belongs next to 'unreferenced_candidates()' (the candidate-generation half) rather than in the posterior-computation package. It still requires both a TaxaLikely likelihood object and a TaxaExpect-derived unreferenced-species list, so it must still run after both are available and before 'TaxaAssign::compute_posterior()' - that is a workflow-ordering requirement, not a package-dependency one, since this function only ever consumes plain data frames and never calls into ...

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_df | yes |  | Data frame -- the $likelihoods component returned by evaluate_likelihoods(). Must contain observation_id, taxon_name, taxon_name_rank, hypothesis_type, score_likelihood, score_likelihood_mean, score_likelihood_sd. |
| unreferenced_df | yes |  | Data frame of unreferenced but plausible species. Must contain columns species (binomial name), genus, and family. Built from TaxaExpect rows confirmed as unreferenced by audit_barcode_coverage(). May optionally contain an observation_id column: a row with NA (or when the column is absent entirely) applies to every observation sharing its genus/family, the original global-list behavior; a row with a real observation_id applies only to that one observation. This lets a caller inject a species that IS globally referenced (so it would never appear via audit_barcode_coverage()) but lacks reference evidence covering one specific query's region -- see restore_suppressed_candidates()'s check_regional_overlap mechanism, whose rejected congeners are returned in exactly this shape via attr(result, "regional_unreferenced"). |

**Value:** 'likelihood_df' with generic '"unreferenced_species"' and '"unreferenced_genus"' rows replaced by named species rows where matches are found. Column set is unchanged; new rows carry 'NA' for most extra columns in the input (e.g. 'constraint_applied', which is genuinely row-specific), except 'score_likelihood_cov', 'score_likelihood_evidence', and 'h2_delta_source' when present - these, like 'score_likelihood'/ 'score_likelihood_mean'/'score_likelihood_sd', describe the shared H2/H3 value itself (identical across every expanded species under one generic row) rather than anything row-specific, so they are copied through too.

#### Withheld rows

A species whose genus has references for this marker (any genus with a specific_candidate row anywhere in likelihood_df) is never named from a FAMILY ring: its genus's references were compared with the read and did not match within the reporting window, so "an unreferenced genus of this family" cannot be it. It is still named from its genus ring when that ring is present. The rows so withheld are listed in attr(result, "unreferenced_withheld") (observation_id, taxon_name, genus, family, reason) and counted in a message; the data frame is present, possibly empty, on every return.

### fetch_bold_reference_sequences(taxa, barcode_term = NULL, rank_system = c("family", "genus", "species"), max_per_species = NULL, include_location = TRUE)

Fetch reference sequences from BOLD Systems for model building

Searches BOLD's v5 Data Portal API by taxon name and returns a 'reference_df' ready for 'build_sequence_matrix()' - the BOLD analog of 'fetch_ncbi_reference_sequences()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxa | yes |  | Character vector of taxon names to search. Each is resolved and queried separately; results are combined and de-duplicated by processid. |
| barcode_term | no | NULL | Character vector of BOLD marker codes to keep (e.g. "COI-5P"), matched against the returned marker_code column. NULL (default) keeps every marker returned. |
| rank_system | no | c("family", "genus", "species") | Character vector of taxonomy ranks, coarse to fine (default c("family", "genus", "species")). Resolved from BOLD's own taxonomy columns (kingdom, phylum, class, order, family, subfamily, genus, species, subspecies -- confirmed against a live query). |
| max_per_species | no | NULL | Integer or NULL (default NULL). Maximum sequences per species (stratified downsampling), matching fetch_ncbi_reference_sequences()'s convention. Requires "species" to be in rank_system. |
| include_location | no | TRUE | Logical (default TRUE). Keep the lat/lon/country columns parsed from BOLD's own coord/country/ocean fields. NA where BOLD has no collection-location metadata (common -- most BOLD records are GenBank-mined and carry no field-collection coordinates). |

**Value:** A data frame ('reference_df') with columns: 'composite_id' BOLD 'processid'. 'sequence' DNA sequence string (BOLD's 'nuc' field). rank columns One column per rank in 'rank_system'. 'lat', 'lon', 'country' Only when 'include_location = TRUE'. Ready for input to 'build_sequence_matrix()'.

#### Details

Talks directly to BOLD's live v5 Data Portal API (https://portal.boldsystems.org/api) via a 3-stage flow: query/preprocessor resolves a taxon name into a formal query triplet, query submits it and returns a query_id, and documents/{query_id}/download returns the matching records. No API key required. Confirmed live and documented directly against BOLD's own OpenAPI spec (https://portal.boldsystems.org/openapi.json) -- this does NOT wrap the bold R package, whose bold_seqspec()/bold_identify() target BOLD's now-retired v3/v4 API and no longer work.

No server-side marker/locus filter exists. BOLD's query API only supports tax/geo/ids/bin/recordsetcode scopes -- there is no marker/gene scope the way NCBI's [GENE] field tag provides via fetch_ncbi_reference_sequences(). barcode_term is therefore applied as a client-side filter on the returned marker_code field (e.g. "COI-5P", "COI-3P") after download, not as part of the query itself -- every record for the taxon is fetched regardless of marker.

Location comes free, like BOLD's own coord/country/ocean fields: no separate round trip is needed the way NCBI requires one (include_location on fetch_ncbi_reference_sequences() triggers a real second fetch) -- BOLD's query already returns these fields, so this parameter just controls whether to keep or drop the columns.

### fetch_ncbi_reference_sequences(taxa, barcode_term, rank_system = c("family", "genus", "species"), min_len = NULL, max_len = NULL, max_per_species = NULL, max_per_genus = 500L, priority_taxa = NULL, max_sequences = 10000L, min_per_taxon = 50L, blacklist_regex = paste0("uncultured|environmental|predicted|", "vector|synthetic|unverified"), min_date = NULL, max_date = NULL, cache_dir = tools::R_user_dir("TaxaLikely", "cache"), ncbi_api_key = NULL, include_location = FALSE, keep_out_of_range = FALSE, max_out_of_range_per_species = 2L, max_out_of_range_len = 200000L, count_attempts = 3L, on_count_failure = c("warn", "error"), evict_unreachable_cache = TRUE, taxa_lineage = NULL, dry_run = FALSE)

Fetch reference sequences from NCBI for model building

Searches NCBI nucleotide by taxon name and barcode marker, retrieves full taxonomy via the NCBI taxonomy database, filters by sequence length and quality, optionally downsamples, and returns a 'reference_df' ready for 'build_sequence_matrix()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxa | yes |  | Character vector of taxon names to search. Can be any rank: species, genus, family, order, or class (e.g., "Fundulus", "Gobiidae", "Actinopterygii"). Each taxon is searched separately; results are combined. |
| barcode_term | yes |  | Character scalar or vector of marker names (e.g., "12S", c("COI", "Co1", "Coxi")). Multiple synonyms are OR-ed in the NCBI query. |
| rank_system | no | c("family", "genus", "species") | Character vector of taxonomy ranks, coarse to fine (e.g., c("family", "genus", "species")). These ranks are resolved from the NCBI taxonomy database. |
| min_len | no | NULL | Integer or NULL. Minimum sequence length (bp). If NULL, auto-resolved from barcode_term using built-in defaults. |
| max_len | no | NULL | Integer or NULL. Maximum sequence length (bp). If NULL, auto-resolved from barcode_term. Set both to NULL and supply wide manual values to cast a broader net (useful for exploring how sequence length relates to errors). |
| max_per_species | no | NULL | Integer or NULL (default NULL). Maximum sequences to retain per species. NULL disables species-level capping. See @section Choosing max_per_species and max_per_genus. |
| max_per_genus | no | 500L | Integer or NULL (default 500). Maximum sequences per genus after species-level capping. NULL disables the cap. See @section Choosing max_per_species and max_per_genus. |
| priority_taxa | no | NULL | Character vector or NULL (default NULL). Species names that should be fully represented in the reference. Typically the species from the user's match data. When total NCBI hits exceed max_sequences, priority species are searched individually and given full allocation; the remaining budget is split proportionally across the broader taxa (families/genera). This ensures the model has good within-species and between-species distances for species that actually appear in the query data. |
| max_sequences | no | 10000L | Integer (default 10000). Safety valve for total download volume. If the total NCBI hit count exceeds this, sequences are subsampled proportionally across taxa (each taxon gets at least min_per_taxon sequences). Priority taxa (if provided) are fetched first; the remaining budget is allocated to broader family searches. |
| min_per_taxon | no | 50L | Integer (default 50). When subsampling due to max_sequences, each taxon is guaranteed at least this many sequences (or all of them if fewer exist). |
| blacklist_regex | no | paste0("uncultured\|environmental\|predicted\|", "vector\|synthetic\|unverified") | Character scalar. Regex pattern for filtering sequence titles. Sequences whose title matches this pattern are excluded. |
| min_date | no | NULL | Character or NULL (default; e.g. pass "2010/01/01" to set one). Earliest publication date for sequences. NULL means no lower bound -- internally resolved to the sentinel "1900/01/01" (predates GenBank's own founding), not left off the query entirely, so it composes safely with a supplied max_date alone. |
| max_date | no | NULL | Character or NULL (default; e.g. pass "2024/12/31" to set one). Latest publication date. NULL means no upper bound -- internally resolved to the sentinel "3000/12/31", matching min_date's NULL handling above. |
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Character path. Per-taxon intermediate results are cached here, enabling resumable downloads when NCBI rate-limits or the session is interrupted. Default tempdir() (clears on R restart). Set to a persistent path for cross-session caching, or NULL to disable. |
| ncbi_api_key | no | NULL | Character or NULL. NCBI API key (increases rate limit from 3 to 10 requests/second). Can also be set via the ENTREZ_KEY environment variable. |
| include_location | no | FALSE | Logical (default FALSE). When TRUE, fetches each accession's full GenBank record (a real, separate NCBI round trip -- not free) and adds lat/lon/country columns parsed from the source feature's lat_lon/country qualifiers. NA where the record has no collection-location metadata (common for older/predicted sequences). Neither .fetch_summaries_batched() (ESummary) nor .fetch_taxonomy_map() (taxonomy DB) -- the two record types this function otherwise fetches -- carry these qualifiers, so this is a genuinely separate fetch, not a free re-parse of existing output. |
| keep_out_of_range | no | FALSE | Logical (default FALSE). When TRUE, sequences outside [eff_min_len, eff_max_len] (e.g. complete mitogenomes) are kept -- tagged via the new in_barcode_range output column -- instead of being dropped, capped separately per species by max_out_of_range_per_species so they never compete with in-range sequences for the max_per_species/max_per_genus training-set budget. Default FALSE preserves this function's original behavior exactly. Exists so a caller needing to check whether a species has ANY real sequence overlapping a specific genomic region (not just whether it has some barcode-length reference) can do so locally against reference_df, without a separate on-demand NCBI fetch -- see restore_suppressed_candidates()'s regional-overlap check. |
| max_out_of_range_per_species | no | 2L | Integer (default 2L). Cap on out-of-range sequences retained per species when keep_out_of_range = TRUE. Ignored otherwise. |
| max_out_of_range_len | no | 200000L | Integer (default 200000L). Upper bound on how large a sequence can be to still be retained under keep_out_of_range = TRUE. Without this, a well-sequenced species' whole-genome scaffold (a real case found in production use: 111 million bp, not a mitogenome) would be retained just as readily as a real ~15-20kb mitogenome, making any later alignment against it pathologically slow for no benefit -- a scaffold that large was never a candidate for "the rescuable barcode region is embedded in this over-length submission" the way a mitogenome or chloroplast genome is. The default comfortably covers any real animal mitogenome or plant chloroplast genome (~120-160kb) with margin, while excluding genome/ scaffold-scale sequences by orders of magnitude. Ignored when keep_out_of_range = FALSE. |
| count_attempts | no | 3L | Integer (default 3L). How many times to try each per-taxon NCBI count query before giving up on it. A count query can fail transiently, typically NCBI throttling, which rentrez often surfaces as the unhelpful message "subscript out of bounds". Retries use exponential backoff on top of the usual inter-request delay. |
| on_count_failure | no | c("warn", "error") | One of "warn" (default) or "error". What to do when a taxon's count query still fails after count_attempts tries. This is not a cosmetic condition. A failed count is excluded from the sequence budget, which sets that taxon's fetch cap to zero, so the taxon contributes NO reference sequences at all and any species-level call within it later rests on no reference data of its own. Observed for real on a PtConception 12S run: 7 taxa failed (the first 7 queried, after which every remaining query succeeded), silently costing 352 species-level consensus rows their own reference data, including Medialuna californiensis, Zalophus californianus and Tursiops truncatus. Re-issuing the identical queries afterwards succeeded for all 7, confirming the failures were transient. "warn" keeps the run alive but reports the affected taxa by name in one consolidated warning and message, because per-taxon warnings are easy to miss in a large log (a real 17,000-line log missed all 7). Use "error" for an unattended production run where a silently degraded reference database is worse than a failed run. |
| evict_unreachable_cache | no | TRUE | Logical (default TRUE). When a taxon's cache file is WRITTEN, also delete that same taxon's cache files whose names the current key cannot produce for any arguments -- superseded generations left behind by an earlier key widening. This is the only part of this function that deletes anything, and it is deliberately narrow: the test is a proof, not a heuristic (see .ref_cache_grammar()), it is scoped to the one taxon just rewritten, it never touches a file over 5 MB, and it says what it removed. Two files that differ only in a key VALUE -- different length bounds, a different rank_system -- are different queries, not generations, and are never touched. Set FALSE to keep every historical generation. |
| taxa_lineage | no | NULL | Data frame or NULL (default). Opt-in homonym protection: a taxon column matching entries of taxa, plus any of rank, kingdom, phylum, class, order, family -- the caller's OWN declared lineage for each queried taxon. A taxon NAME is not a key -- NCBI can hold several nodes with the same name in unrelated lineages (e.g. a genus of red algae named "Vertebrata" beside the vertebrate clade of the same name; see TaxaTools::resolve_ncbi_taxid()'s own examples for confirmed real cases), and the default [Organism] name-based query silently resolves to whichever node NCBI prefers, which for an [ORGN] search is any node in the lineage -- a higher-rank or larger-volume homonym wins on volume, drowning the wanted sequences in results from the wrong organism entirely (a red-algal genus query for "Vertebrata" measured returning 306,181 vertebrate sequences alongside 68 real red-algal ones -- see ecosystem_docs/REENTRY_PROMPT_homonym_detection.md for the full incident). When supplied, each taxon is resolved to a disambiguated NCBI taxid first, via TaxaTools::resolve_ncbi_taxid() using rank and the declared lineage as discriminators, and queried by txid<id>[ORGN] instead of <name>[Organism]; a taxon that remains ambiguous after both discriminators falls back to the name-based query with no protection, exactly as if taxa_lineage had not named it. Also enables a post-fetch lineage-agreement guard needing no extra API call: every fetched sequence's own returned kingdom/phylum/family is compared against the taxon's declared lineage, and any row sharing nothing with it (a likely homonym slipping past taxid resolution, or a taxon this parameter didn't cover at all) is recorded in attr(reference_df, "lineage_disagreements") -- checked, not silently trusted, since agreement doesn't require an exact match (a benign taxonomic revision that stays within a shared higher clade also agrees). NULL (the default) reproduces this function's original behaviour exactly: every taxon queried by bare name, no guard. |
| dry_run | no | FALSE | Logical (default FALSE). TRUE stops after the metadata step, before any sequence is downloaded, and returns the memory the sequence matrix would need under a grid of caps instead of a reference_df. The metadata it fetches is the metadata the real run needs, and it is cached, so a dry run followed by the real run makes no more NCBI requests than the real run alone; on a warm cache a dry run makes none beyond the count queries of uncached taxa. See @return. |

**Value:** A data frame ('reference_df'), carrying a 'count_failures' attribute (always present, possibly zero-length) naming any taxa dropped because their count query failed - check it with 'attr(reference_df, "count_failures")' rather than reading the log. Columns: 'composite_id' NCBI accession (version suffix stripped). 'sequence' DNA sequence string. rank columns One column per rank in 'rank_system' (e.g., 'family', 'genus', 'species'). 'in_barcode_range' Logical. 'TRUE' for sequences within [eff_min_len, eff_max_len]; 'FALSE' for out-of-range sequences retained only when 'keep_out_of_range = TRUE' (always 'TRUE' when 'keep_out_of_range = FALSE', the default, since out-of-range rows are dropped entirely in that case). 'slen' Integer. Sequence length as reported by NCBI, for reference alongside 'in_barcode_range'. 'lat', 'lon', 'country' Only when 'include_location = TRUE'. Collection location parsed from GenBank's 'lat_lon'/'country' qualifiers; 'NA' when absent or unparseable. 'queried_taxon', 'kingdom', 'phylum' Only when 'taxa_lineage' was supplied. 'queried_taxon' records which 'taxa' entry a row was fetched under; 'kingdom'/'phylum' are always resolved (in addition to whatever 'rank_system' itself requests) so the lineage-agreement guard has data to check without a second taxonomy fetch. Carries a 'taxa_without_sequences' attribute: the requested taxa for which nothing came back. Check it after every fetch: a name that resolves to the wrong NCBI node can return nothing, and an empty result is otherwise indistinguishable from a taxon with no barcode. Also carries a 'lineage_disagreements' attribute (always present when 'taxa_lineage' was supplied; absent otherwise) - a data frame of every row whose returned lineage shared nothing with its queried taxon's declared lineage, via 'attr(reference_df, "lineage_disagreements")'. Ready for input to 'build_sequence_matrix()' (which applies its own, independent length filter - out-of-range rows kept here are excluded from training there exactly as before this parameter existed). With 'dry_run = TRUE', instead a list: 'taxa' (one row per requested taxon: 'ncbi_count', 'NA' for a taxon served from cache; 'cached'; 'sequences', the in-range sequences found for it), 'sequences' (one row per in-range sequence, uncapped: accession and rank columns), and the elements of 'estimate_sequence_matrix_size()' for this call's caps plus 'max_per_species' in {none, 20, 10} and 'max_per_genus' in {none, 1000, 500, 250}: 'grid', 'species_dropped', 'available_gb', 'budget_gb' and 'rates'. The grid is also printed. Pass 'sequences' to 'estimate_sequence_matrix_size()' to try other caps or build settings.

#### Details

The function performs a count-first estimation before downloading. If the total exceeds max_sequences, sequences are subsampled proportionally across taxa (each taxon gets at least min_per_taxon sequences). This ensures all taxa are represented while staying within the download budget.

#### Why not use match object accessions

The match object from TaxaMatch contains only sequences that happened to match your queries -- a biased subset. A good likelihood model needs the broader landscape: within-species variation, between-species distances, and coverage of related taxa. This function searches by taxon + marker to get that full picture.

#### Caching and resumability

For large searches (many taxa, slow NCBI responses), set cache_dir to a directory path. Completed per-taxon results are saved as .rds files. If the function is interrupted, re-running with the same cache_dir skips already-downloaded taxa.

The per-taxon files hold every sequence's metadata, uncapped; sequences are kept in a separate per-accession store under cache_dir/fasta. max_per_species and max_per_genus are applied when the reference is assembled, so changing either re-uses the cached metadata and downloads only sequences not already in the store. A per-taxon file written under a cap holds only a sample, cannot serve a larger cap, and is re-fetched once.

#### Choosing max_per_species and max_per_genus

The memory build_sequence_matrix() and train_likelihood_model() need grows with the square of the number of sequences in each genus, so a few heavily sequenced genera decide whether a run fits. One real COI genus, Delia, held 14,470 sequences in 31 species, 13,114 of them in one.

Cap species first. max_per_species never removes a species; it thins the over-sequenced ones, which is where that bloat is (Delia fell to 321 sequences at 20 per species, all 31 species kept). max_per_genus is the second lever and the safety net: it samples across the whole genus, so a genus with more species than the cap allows loses whole species, and the likelihood model's between-species terms are fitted on the species that remain. Neither cap reduces the part of the cost that grows with the square of the number of genera; only a narrower taxon list does (see estimate_sequence_matrix_size()).

Both caps keep the same sequences on every call: each accession has a fixed pseudo-random rank, and a cap keeps the lowest-ranked. A smaller cap keeps a subset of what a larger one kept.

To choose values from numbers rather than by trial, run once with dry_run = TRUE: it reports, for each combination of caps, the sequences and species kept, the species removed by name, and the predicted memory against the memory this machine has available.

### fetch_xc_recording_locations(species_names, verbose = TRUE)

Fetch per-recording locations from Xeno-canto for one or more species

Thin looping wrapper around '.xc_recording_locations()' - same 1-second-per-species rate limit 'audit_acoustic_coverage' already uses for its own Xeno-canto queries. Unlike 'audit_acoustic_coverage(xc_recordings = TRUE)', which only keeps a per-species recording _count_, this returns the per-recording 'lat'/'lon' the Xeno-canto v3 API already provides in the same response body.

| Param | Required | Default | Doc |
|---|---|---|---|
| species_names | yes |  | Character vector of binomial species names (e.g. "Turdus migratorius"). |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A data frame with one row per recording, across all requested species: 'species', 'xc_id' (Xeno-canto's own catalog number), 'lat', 'lon', 'country'.

#### Details

xc_id is Xeno-canto's own catalog number, not a build_site_table-ready observation_id. Mapping a Xeno-canto recording to a caller's own BirdNET observation_id convention ("\{file_stem\}_\{start\}-\{end\}", per TaxaMatch::read_birdnet_output()) is a harness/study-design concern, not something this function attempts.

### filter_top_hypotheses(likelihood_df, rank_system = NULL)

Keep only the finest-rank specific candidates per query

After 'evaluate_likelihoods()', each query may have specific candidates at multiple ranks (e.g., both species- and genus-level hits). This function retains only the finest-rank specific candidates - coarser candidates are redundant when a finer-rank hit exists - while keeping all '"unreferenced_species"' and '"unreferenced_genus"' rows.

| Param | Required | Default | Doc |
|---|---|---|---|
| likelihood_df | yes |  | Data frame -- the $likelihoods component of the list returned by evaluate_likelihoods(). |
| rank_system | no | NULL | Character vector of rank names coarse to fine. Used to assign numeric rank scores for comparison. Default NULL auto-detects from the taxon_name_rank values in likelihood_df. |

**Value:** Filtered version of 'likelihood_df'.

#### Details

is_restored preservation: When the $likelihoods data frame contains an is_restored column (propagated by evaluate_likelihoods() from restore_suppressed_candidates()), a coarser-rank row (e.g., genus) is preserved instead of dropped when every finer-rank row for the same genus in the same observation has is_restored = TRUE. This situation arises in post-LCA / post-consensus workflows: the genus row is a real LCA-collapsed identification, and the species rows were added purely by restoration (not original BLAST hits). Preserving the genus row allows TaxaAssign::join_priors() to expand it into named species hypotheses -- including locally-expected species absent from the reference library. The all-restored species rows are simultaneously dropped to prevent double-counting after expansion.

### infer_exclude_predicted(match_obj, accession_col = NULL, verbose = TRUE)

Infer whether predicted sequences were excluded from the BLAST reference

Examines accession numbers in a match object to determine whether the BLAST reference database included computationally predicted sequences (NCBI 'XR_' and 'XM_' RefSeq accessions). Returns 'TRUE' if predicted sequences appear to have been excluded - the correct value for 'audit_barcode_coverage''s 'exclude_predicted' argument when using curated databases (Jonah Ventures, SILVA, PR2, MIDORI). Returns 'FALSE' if predicted sequences are present, or 'NA' when the accession column contains only custom (non-NCBI) identifiers and the inference cannot be made.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. A standardised match object as produced by TaxaMatch::standardize_match_data() or a compatible user-supplied table. Must contain an accession column. |
| accession_col | no | NULL | Character scalar or NULL. Name of the accession column. If NULL (default) the function auto-detects a column named "accession", "Accession", "acc", "accno", "AccessionNumber", or "composite_id" (the accession column fetch_ncbi_reference_sequences() writes). |
| verbose | no | TRUE | Logical. If TRUE (default), emits a message explaining the inference and its basis. |

**Value:** A single logical: 'TRUE' (exclude predicted - no 'XR_'/'XM_' accessions found among NCBI-format accessions), 'FALSE' (do not exclude - predicted accessions are present in the match object), or 'NA' (cannot determine - no standard NCBI accessions found; set 'exclude_predicted' explicitly).

#### Details

##### What predicted sequences are

NCBI predicted sequences carry XR_ (predicted ncRNA, including rRNA) or XM_ (predicted mRNA) RefSeq prefixes. They are computationally annotated from whole-genome assemblies and are absent from curated barcode databases used by metabarcoding labs (SILVA, PR2, MIDORI, Jonah Ventures). Counting them as "has sequences in NCBI" incorrectly suppresses unreferenced- species hypotheses for taxa whose only NCBI entry is a predicted record.

##### How inference works

Standard NCBI accessions match the pattern ^([A-Z]{1,2}_[0-9]|[A-Z]{2,4}[0-9]): a RefSeq two-letter prefix followed by underscore + digit (e.g. NR_, XR_, NM_), or a GenBank letter-block immediately followed by digits (e.g. AB123456, KP891234). Custom accessions such as JV_voucher_* or internal lab IDs do not match this pattern and are excluded from the check. When the column contains a mix of custom and NCBI accessions, only the NCBI subset is examined.

##### NA return and fallback

If all accessions are custom (e.g. a fully curated lab database with no NCBI identifiers), or if the match object has no accession column at all (e.g. WilderLab/Mugu workflows where the match object is built directly from ESV taxonomy tables), the function returns NA. Use !isFALSE() to apply a safe default:


```

ep <- infer_exclude_predicted(match_obj) coverage <- audit_barcode_coverage(..., exclude_predicted = !isFALSE(ep)) ```

!isFALSE(ep) is TRUE for both TRUE and NA, and FALSE only when the function confirmed predicted sequences are present. This is safer than ep %||% TRUE because %||% replaces NULL but not NA.

### interpret_model(model_params, print_report = TRUE)

Summarise a trained likelihood model

Converts the internal logit-space parameters of a '"taxa_model_params"' object back to interpretable percentages and prints a formatted report. Returns the summary tables invisibly for programmatic access.

| Param | Required | Default | Doc |
|---|---|---|---|
| model_params | yes |  | Object of class "taxa_model_params" returned by train_likelihood_model(). |
| print_report | no | TRUE | Logical (default TRUE). If FALSE, suppresses console output. |

**Value:** An invisible named list with elements: 'hypothesis_baselines' Data frame: expected match % and expected gap % for H1, H2, H3. The gap is the difference between the best match and the runner-up. H2/H3 have gap near 0 because when the true species or genus is absent, no candidate has a clear advantage. 'global_h1' Data frame: global mean score, gap, and SD. 'hierarchy' Data frame: per-rank counts and averages. 'species_thresholds' Data frame: per-species expected match %, gap %, and status classification. 'raw_sigma' The 2x2 covariance matrix from the model.

### match_reference_region(reference_df, esv_sequences, barcode_term = NULL, primer_fwd = NULL, primer_rev = NULL, min_coverage = 0.8, max_mismatch_rate = 0.15, keep_unplaced = FALSE, n_candidates = 3L, n_cores = 1L, verbose = TRUE)

Trim reference sequences to the region the study's ESVs cover

The likelihood model is trained on identities between pairs of reference sequences ('build_sequence_matrix()') and applied to identities between an ESV and a reference. The two scales are comparable only if both are measured over the same stretch of the gene. GenBank deposits rarely are: they may be longer than the amplicon (a full barcode, a whole gene, a mitogenome), cover a different stretch of the same gene (an 18S V4 deposit in a V9 study; a non-MiFish stretch of 12S), or stop part-way into it. 'build_sequence_matrix()''s length window cannot tell these apart: it keeps a 655 bp ...

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with at least composite_id and sequence (the object fetch_ncbi_reference_sequences() returns and build_sequence_matrix() consumes). |
| esv_sequences | yes |  | Character vector of the study's ESV (ASV/OTU) sequences, as submitted to the reference search. Duplicates are ignored. These define the region. |
| barcode_term | no | NULL | Character scalar or NULL. Used only to look up a registered primer pair for the fallback, via TaxaTools::resolve_barcode_primers(). A term with no registered pair, or an ambiguous one such as "18S", simply disables the fallback. |
| primer_fwd | no | NULL | Character scalars, 5' to 3', IUPAC allowed. Supply both, or neither (to use barcode_term). |
| primer_rev | no | NULL | Character scalars, 5' to 3', IUPAC allowed. Supply both, or neither (to use barcode_term). |
| min_coverage | no | 0.8 | Numeric in (0, 1] (default 0.8). Smallest share of the ESV span a placed reference must cover. Use the same value as build_sequence_matrix()'s min_pair_coverage. |
| max_mismatch_rate | no | 0.15 | Numeric in [0, 1) (default 0.15). Fraction of primer positions allowed to mismatch in the primer fallback, as in trim_to_amplicon(). |
| keep_unplaced | no | FALSE | Logical (default FALSE). TRUE keeps unplaced rows, with their sequence as deposited, so they can be inspected. build_sequence_matrix() refuses such a data frame until they are dropped. |
| n_candidates | no | 3L | Integer (default 3L). Candidate ESVs aligned per reference. |
| n_cores | no | 1L | Integer (default 1L). Forked worker processes (parallel::mclapply(); must be 1 on Windows). |
| verbose | no | TRUE | Logical (default TRUE). |

**Value:** 'reference_df', with 'sequence' replaced by the region for placed rows, unplaced rows dropped (unless 'keep_unplaced'), and five columns added: 'trim_path' How the row was handled: '"esv_aligned"', '"esv_aligned_reverse_complement"', '"primer_anchored"', '"primer_anchored_reverse_complement"' (placed), or '"short_of_region"', '"not_placed"', '"invalid_sequence"' (unplaced). The vocabulary extends TaxaMatch's 'query_trim_path'. 'len_submitted' Length of the sequence as deposited. 'region_coverage' Share of the ESV span the placed sequence covers. 'region_identity' Identity to the ESV it was aligned to ('NA' for primer anchoring). 'homology_score' Overlap-alignment score of that alignment. Attributes: 'homology_threshold', 'region_length' (median ESV length), and 'trim_path_counts' (counts over ALL input rows, including dropped ones).

#### Details

match_reference_region() places every reference on the region the ESVs themselves cover, so it needs no primer pair and works for any marker:

- For each reference (both strands), the ESVs sharing the largest fraction of their 8-mers with it are taken as candidates.

- The reference is aligned to each candidate with an overlap alignment (end gaps free), and the best-scoring alignment is kept.

- The alignment counts as homologous only if its score exceeds every score obtained by aligning the REVERSED (not complemented) and the COMPLEMENTED (not reversed) references to the same ESVs. Both transforms keep a record's length and base composition and destroy its homology, so they give an empirical no-homology null without assuming an identity floor. A shuffled null would also keep composition, but it needs a random draw, so a result would depend on the RNG state. An identity floor (for example 1 - max_dist) would be wrong here: on CalIntertidal COI the median identity of a GenBank reference to its closest ESV is about 80%, the same as the median BLAST score of the study's own match object.

- The ESV's ends are projected onto the reference, and the reference is cut to that span. A span covering less than min_coverage of the ESV is a partial deposit and is not placed.

- References the alignment did not place fall back to primer anchoring, when a primer pair is available. One primer site is enough: the span starts after the forward site (or ends before the reverse site) and runs for the median ESV length.

A reference that cannot be placed is never used whole: absence of an anchor is not evidence that a record already is the amplicon. Unplaced rows are dropped unless keep_unplaced = TRUE, and every row records how it was handled in trim_path.

#### Pipeline placement

Between the reference fetch and build_sequence_matrix():


```

reference_df <- fetch_ncbi_reference_sequences(...) reference_df <- match_reference_region(reference_df, esv_sequences = match_df$sequence, barcode_term = "COI-Leray") seq_matrix <- build_sequence_matrix(reference_df, barcode_term = "COI-Leray", ...) ```

build_sequence_matrix() recognises the trim_path column and does not apply barcode_term's deposit-length window to region-matched sequences (a Leray region of 250-313 bp would otherwise fail COI's 300-900 bp window).

Rebuilding the matrix from region-matched references changes the trained model, so the query-noise calibration and every likelihood computed from the old matrix must be recomputed.

#### Region matching needs the study's own matched references

Region matching removes every reference that does not cover the ESV span, so it is only as good as the reference set's coverage of that span. A fetch by taxon name and marker term can return mostly other stretches of the gene: on an 18S V9 study, 73% of the fetched references lacked V9, and only 950 of the 6,902 accessions the ESVs actually matched had been fetched at all. Region matching that set alone cut the trained species from 5,347 to 2,098 and the share of observations won by a referenced species from 10% to 1.6%. Adding the match object's own accessions (they cover the span by construction, since the ESVs matched them) before calling this function restored coverage, and training on the result did no worse than training on the unmatched set (12% won by a referenced species). Do not adopt region matching without that step.

The added accessions came to the reference set because the queries matched them, so pairs between two of them are tighter than pairs between fetched references (within-species variance about 60% as large in that study). They were 4.7% of within-species pairs there. A guard that drops such a pair only when its species also has a pair involving a fetched reference keeps every species trainable; the remaining bias then sits in low-coverage species, whose only pairs come from added accessions.

#### Batch dependence

The homology threshold is the largest null score in the call, so it rises slowly with the number of references, and with only a handful of references it is low. It decides only whether an unplaced record is reported as "short_of_region" (homologous but partial) or "not_placed" (no homology): a placed record must also cover min_coverage of the ESV, which a chance alignment does not. Call this once on the whole reference set rather than on pieces of it; the threshold used is returned in attr(, "homology_threshold").

### read_crabs_output(crabs_file, rank_system = NULL, max_n_bases = NULL, require_species = TRUE, dereplicate = FALSE)

Read a CRABS-formatted reference database

Reads the internal output format produced by CRABS (Creating Reference databases for Amplicon-Based Sequencing; Jeunen et al. 2023), a widely-used eDNA reference database builder. CRABS outputs a single tab-delimited file with no header row and 11 fixed columns, with missing ranks represented as the literal string '"NA"'.

| Param | Required | Default | Doc |
|---|---|---|---|
| crabs_file | yes |  | Character scalar. Path to the CRABS internal-format file. |
| rank_system | no | NULL | Character vector of ranks to include, coarse to fine (e.g., c("family", "genus", "species")). Must be a subset of the seven CRABS taxonomy columns: kingdom, phylum, class, order, family, genus, species. Default NULL auto-detects from the file: all columns that have at least one non-NA value are included. For likelihood model training, c("family", "genus", "species") is typically sufficient. |
| max_n_bases | no | NULL | Integer or NULL (default NULL). Drop sequences longer than this many bases. Useful for removing chimeric or incorrectly-assembled entries that CRABS length filters may have missed. NULL retains all lengths. |
| require_species | no | TRUE | Logical (default TRUE). When TRUE, rows with a missing or invalid species name are dropped. Validity is checked by TaxaTools::is_plausible_binomial(), which rejects sp., cf., aff., and uncultured names. Set to FALSE to retain genus-level-only references. |
| dereplicate | no | FALSE | Logical (default FALSE). When TRUE, exact-duplicate sequences within the same species are collapsed to one representative (first accession retained). CRABS itself offers primer- trimmed dereplication; this option works on the raw sequence column and is a complement, not a replacement. |

**Value:** A data frame ('reference_df') with columns: 'composite_id' Accession string (version suffix stripped). rank columns One column per rank in 'rank_system'. 'sequence' DNA sequence string. Ready for input to 'build_sequence_matrix()'.

#### CRABS column format

CRABS internal format is a headerless tab-delimited file with exactly 11 columns in this fixed order:


```

accession | taxid_string | ncbi_tax_number | kingdom | phylum | class | order | family | genus | species | sequence ```

Generate this file with crabs db_download, crabs db_import, and crabs db_merge.

#### Complementary role with reference-quality screening

CRABS handles efficient sequence retrieval and bulk quality filters at the database-building stage (e.g., length range, primer trimming, taxonomic scope, exact dereplication). It does not catch mislabeling errors: sequences where the taxonomic label is wrong but the sequence is otherwise valid, which inflate within-species distance estimates and produce unreliable likelihoods. After loading a CRABS database with this function, screen it via TaxaMatch::corroborate_references_locally() + TaxaMatch::evaluate_reference_accessions() before training the likelihood model -- see train_likelihood_model()'s own documentation for the exact pattern.

### read_reference_fasta(fasta_path, taxonomy = NULL, rank_system, taxonomy_file = NULL)

Read a local FASTA file into a reference data frame

Reads a FASTA file and joins it to a user-supplied taxonomy table to produce a 'reference_df' suitable for 'build_sequence_matrix()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| fasta_path | yes |  | Character scalar. Path to a FASTA file (.fasta, .fa, .fna). |
| taxonomy | no | NULL | Data frame with a composite_id column and one column per rank in your rank system. composite_id values must match the accessions parsed from FASTA headers. Supply either taxonomy or taxonomy_file, not both. |
| rank_system | yes |  | Character vector of rank names, coarse to fine (e.g., c("family", "genus", "species")). Used to validate that all rank columns are present in taxonomy, or to determine which ranks to extract from taxonomy_file. |
| taxonomy_file | no | NULL | Character scalar or NULL (default). Path to a 2-column taxonomy TSV file (see section above). Supply either taxonomy_file or taxonomy, not both. Requires rank_system to be specified explicitly. |

**Value:** A data frame ('reference_df') with columns 'composite_id', 'sequence', and one column per rank. Ready for input to 'build_sequence_matrix()'.

#### Details

This is the local-file alternative to fetch_ncbi_reference_sequences(). Use it when you already have a reference database on disk (e.g., a CRUX database, a GenBank download, or a custom curated FASTA).

#### CRABS databases

If your FASTA was produced by CRABS, use read_crabs_output() on the CRABS internal-format file instead. It reads the taxonomy embedded directly in that file without requiring a separate taxonomy table.

#### Taxonomy table format

The taxonomy table must contain a composite_id column that matches the identifiers extracted from FASTA headers, plus one column per rank in your rank_system. FASTA header identifiers are extracted as the first whitespace-delimited token after >, with version suffixes (.1, .2) stripped.

Example:


```

composite_id, family, genus, species NC_001606, Fundulidae, Fundulus, Fundulus heteroclitus NC_012361, Fundulidae, Fundulus, Fundulus parvipinnis ```

#### Taxonomy file format (QIIME2 / RESCRIPt / SILVA / MIDORI2)

Supply taxonomy_file instead of taxonomy when your taxonomy lives in a 2-column tab-delimited file where column 1 is the sequence ID and column 2 is a semicolon-delimited taxonomy string. Two sub-formats are supported:

- Prefix-style (QIIME2, RESCRIPt, SILVA): k__Kingdom;p__Phylum;c__Class;o__Order;f__Family;g__Genus;s__Species

- Positional (MIDORI2, plain SILVA): Kingdom;Phylum;Class;Order;Family;Genus;Species

A single header row starting with Feature or feature is automatically detected and skipped.

### report_likelihood(model, verbose = FALSE)

Generate a Report Section for Likelihood Estimation

Summarizes a trained likelihood model into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| model | yes |  | A taxa_model_params object from train_likelihood_model. |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing the likelihood model. results Template text summarizing model diagnostics. params Named list of model parameters. statistics Named list of model diagnostics.

### restore_suppressed_candidates(match_obj, reference_df, rank_system = NULL, score_col = "score_original", observation_id_col = "observation_id", delta = 0.5, max_per_obs = 10L, model_params = NULL, alpha = 0.001, max_dist = 0.25, check_regional_overlap = FALSE, seq_matrix = NULL, min_regional_coverage = 0.5, accession_col = "accession", sequence_col = NULL, candidate_species_filter = NULL, taxaexpect_priors = NULL, grid_id_col = "grid_id", taxon_col = "taxon_name", grid_col = "grid_id", theta_col = "theta_mean", budget_ratio_cap = 19, max_level4_per_anchor = 10L, min_query_coverage = 0.8, dropped_matches = NULL, measured_offset = NULL, verbose = TRUE)

Restore candidates suppressed by upstream pipeline rules

This function's job is not "restore candidates so more of them can individually win" but to detect whether the anchor's apparent win is real or an artifact of upstream suppression, so that downstream consensus logic can back off from a false-precision specific-species call when it isn't. Every same-genus congener in 'reference_df' not already present for an observation is checked, for _every_ observation, regardless of whether 'detect_suppressed_candidates()' finds a global pipeline pattern - admission does not depend on a globally detected rule. A congener is admitted as an ordinary ...

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. Standardised match object. |
| reference_df | yes |  | Data frame. Reference database (output of fetch_ncbi_reference_sequences(), read_reference_fasta(), or read_crabs_output()). Must contain the same genus/species columns as match_obj. |
| rank_system | no | NULL | Character vector or NULL. Rank columns coarse-to-fine (e.g. c("family","genus","species")). Auto-detected when NULL. |
| score_col | no | "score_original" | Character. Score column name (default "score_original"). |
| observation_id_col | no | "observation_id" | Character. Observation ID column name (default "observation_id"). |
| delta | no | 0.5 | Numeric. Only used by the no-score pathway (see @details) -- score gap between H1's synthetic 1.0 and a restored row's synthetic score (default 0.5, on the 0-100 scale; used as delta / 100 against the 1.0 baseline). Has no effect when match_obj carries real scores -- restored rows there get a real, hierarchy-resolved score instead (@section Score-sourcing hierarchy). |
| max_per_obs | no | 10L | Integer. Maximum restored candidates per observation (default 10L), applied to the final admitted set (after Purpose A/B gating), not to the raw congener list. |
| model_params | no | NULL | A taxa_model_params object (output of train_likelihood_model()) or NULL (default). Used two ways: (1) Purpose A's outlier test needs the anchor species' own sigma (H1_Lookup, floored at H1_Sigma[1,1], matching evaluate_likelihoods()'s own convention) -- Purpose A never admits any candidate when this is NULL; (2) Level 3 of the score-sourcing hierarchy prefers H2_Lookup$delta_shrunk (the model's own genus-specific congener-divergence estimate) over a raw seq_matrix median when available, keeping a restored row's imputed score consistent with the same estimate evaluate_likelihoods() already uses for that genus's H2 rows. |
| alpha | no | 0.001 | Numeric (default 0.001). Purpose A's outlier-test p-value cutoff -- identical parameter and identical test to evaluate_likelihoods()'s own alpha, reused rather than inventing a second calibrated constant for the same question. |
| max_dist | no | 0.25 | Numeric (default 0.25). Purpose B's admission floor, on the same distance (1 - p_match) scale as build_sequence_matrix()'s own max_dist -- reuse the same value passed there for consistency. |
| check_regional_overlap | no | FALSE | Logical (default FALSE). When TRUE, enables the score-sourcing hierarchy's Level 4 (live Tier 2 pairwise alignment, @section Score-sourcing hierarchy) for candidates that Levels 1-3 can't resolve for free -- without it, such candidates simply get no score and are never restored. Requires accession_col in match_obj and composite_id/ sequence in reference_df (errors if absent). This also doubles as Purpose A's regional-overlap guarantee for real, without a second position check: any candidate resolved via Levels 1-3 is position-safe by construction (seq_matrix only ever contains properly-sized, in-window sequences), so the regional-overlap concern only ever bites exactly where Level 4 already lives. |
| seq_matrix | no | NULL | Data frame or NULL. Output of build_sequence_matrix() (needs id_x/id_y/p_match/ coverage), the source for Levels 1-3 of the score-sourcing hierarchy and Level 4's Tier 1 lookup. Restoration is a no-op for the scored pathway when this is NULL and check_regional_overlap = FALSE -- there is no free evidence to source a score from and no live alignment enabled either. |
| min_regional_coverage | no | 0.5 | Numeric in (0, 1]. Minimum alignment coverage required for Level 4's live Tier 2 alignment to accept a congener as overlapping (default 0.5). Only used when check_regional_overlap = TRUE. |
| accession_col | no | "accession" | Character. Column in match_obj naming each row's own reference accession (default "accession"). |
| sequence_col | no | NULL | Character or NULL (default NULL). Column in match_obj carrying each observation's own raw query DNA sequence, enabling Level 4's Tier 2b fallback (see @section Score-sourcing hierarchy) for match objects with no live BLAST alignment coordinates at all. NULL means only Tier 1/2a run. |
| candidate_species_filter | no | NULL | Character vector or NULL (default NULL). Two roles, both cost- or plausibility-related, never a correctness gate on the free hierarchy levels: (1) defines Purpose B's plausible-candidate set; (2) is Level 4's own default cost gate (@section Level 4 cost control) -- a candidate not on this list only reaches the expensive live-alignment step if taxaexpect_priors' ratio test says it's specifically worth it. Never gates Levels 1-3 -- Purpose A's free-tier genus-wide sweep sees every congener regardless of this filter (a plausibility filter cannot make an observation get zero signal, it can only skip the expensive step for an implausible congener). Intended to hold whatever locally-plausible- species list a caller would apply downstream anyway (e.g. TaxaExpect occurrence priors' taxon_name column). Species names must match reference_df's own species_col values exactly (full binomial, e.g. "Fundulus parvipinnis"). NULL (default) means every same-genus congener is both Purpose-B-eligible AND Level-4-eligible -- no narrowing at all, at some real cost (see @section Level 4 cost control for two real, measured cases). |
| taxaexpect_priors | no | NULL | Data frame or NULL (default NULL). A plain data frame -- this package has no dependency on TaxaExpect and never calls into it; the name and default taxon_col/ grid_col/theta_col column names are simply chosen to match TaxaExpect::estimate_kernel_priors()'s own $priors output shape (the current recommended path -- the archived generate_full_priors() used the identical column names), so that object can be passed directly without renaming columns. Any data frame with the right columns (or with taxon_col/grid_col/ theta_col overridden to match your own column names) works. Powers the floor-vs-documented ratio fallback in @section Level 4 cost control for a candidate NOT on candidate_species_filter. NULL (default) means that fallback is unavailable -- a candidate missing the filter is never worth Level 4 regardless of its real occurrence support. |
| grid_id_col | no | "grid_id" | Character. Column in match_obj naming each observation's own grid cell (default "grid_id"), looked up against taxaexpect_priors' grid column. Only used when taxaexpect_priors is supplied. |
| taxon_col | no | "taxon_name" | Character. Column names within taxaexpect_priors for the species/grid/prior-mean columns (defaults "taxon_name", "grid_id", "theta_mean"). |
| grid_col | no | "grid_id" | Character. Column names within taxaexpect_priors for the species/grid/prior-mean columns (defaults "taxon_name", "grid_id", "theta_mean"). |
| theta_col | no | "theta_mean" | Character. Column names within taxaexpect_priors for the species/grid/prior-mean columns (defaults "taxon_name", "grid_id", "theta_mean"). |
| budget_ratio_cap | no | 19 | Numeric (default 19). Derived, not an arbitrary tuning knob: from posterior_consensus()'s min_posterior default of 0.05 and a same-or-worse-than- anchor likelihood bound (@section Level 4 cost control). |
| max_level4_per_anchor | no | 10L | Numeric (default 10L, use Inf to disable). Hard backstop cap on how many distinct candidates get a live Level 4 alignment attempt per anchor accession, independent of candidate_species_filter/taxaexpect_priors -- insurance against a large or absent filter (or a permissive ratio) still forcing an unbounded number of expensive alignments for one anchor. See @section Level 4 cost control. |
| min_query_coverage | no | 0.8 | Numeric in (0, 1] (default 0.8). When sequence_col supplies the query sequence, a restored candidate is scored by aligning the query directly to the candidate's own references (@section Measured restored scores); a reference counts only if its local alignment covers at least this share of the query -- the same share BLAST's query-coverage filter asks of the match data's own scores. |
| dropped_matches | no | NULL | Data frame or NULL (default). Match rows removed from match_obj before this call because their reference accession was dropped (e.g. a reference-screen drop list), with the same columns as match_obj, including sequence_col. For each (observation, genus) among them, every species of that genus with KEPT references in reference_df that the observation does not already hold is offered as a candidate (at most max_per_obs, best first), scored by the same direct alignment (@section Measured restored scores) and added only when a kept reference covers at least min_query_coverage of the query (restoration_basis = "dropped_hit_replacement"). Dropping an accession then no longer drops a genus that has other good references -- including from an observation whose every hit was dropped -- and a congener the dropped label never named can win on its own alignment. Requires sequence_col. |
| measured_offset | no | NULL | NULL (default) or a single number. NULL estimates the banded offset from this call's own match_obj (@section Measured restored scores). A number is subtracted from every measured identity as given (no bands) -- for a marker restored in more than one call, so that a restored score does not depend on which batch its observation landed in. |
| verbose | no | TRUE | Logical. Emit summary messages (default TRUE). |

**Value:** 'match_obj' with restored '"suppressed_candidate"' rows appended (or unchanged if nothing qualified), plus new 'is_restored', 'restoration_basis', 'restoration_level', and 'restoration_source_accession' columns. 'restoration_level' is the '.resolve_hierarchy_score()' level (1-4) that produced a restored row's score, 'NA' for original (non- restored) rows and for the no-score pathway. 'restoration_source_ accession' is a real, single NCBI accession ONLY when 'restoration_level == 1L' AND exactly one candidate accession drove the score - Levels 2-4 always aggregate across more than one accession, so no single accession can be honestly named as "the" source for those; 'NA' otherwise. Lets a caller screen restored rows for reference-accession quality (e.g. 'TaxaMatch::evaluate_reference_accessions()') wherever that's actually possible - distinct from the '"RESTORED_<accession>"' value already carried in 'accession' itself, which always picks an arbitrary representative accession of the candidate species for display/provenance regardless of restoration level, and should not be used for screening (it is not guaranteed to be the accession that actually drove the score). When 'check_regional_overlap = TRUE', the result also carries 'attr(result, "regional_unreferenced")': 'NULL' if nothing was ever rejected/ unresolved, otherwise a data frame with columns 'observation_id'/ 'species'/'genus'/'family'/'basis' - one row per such species per observation, 'basis' either '"regional_reject"' (Level 4 ran and found no position overlap) or '"no_reference_data"' (no evidence could be gathered either way - Level 0 failed and Level 4 also came back empty, or was skipped by the compute-budget mechanism). Ready to 'dplyr::bind_rows()' onto an 'unreferenced_df' before calling 'expand_unreferenced_hypotheses()', whose 'observation_id'- scoped rows accept this shape directly (an extra 'basis' column is additive and does not disturb that consumer). Restored rows also carry 'restored_score_source' ('"measured"' or '"imputed"'), 'restored_reason' (why that source: '"measured_query_alignment"', '"imputed_no_query_sequence"' or '"imputed_query_coverage_below_min"') and 'restored_below_floor' and 'restored_offset_out_of_range'; all are 'NA' on original rows. 'attr(result, "restoration_skipped")' is 'NULL' or a data frame ('observation_id', 'species', 'reason') of candidates that could not be scored at all.

#### Details

- "competitive_score" (Purpose A -- competitiveness detection): the candidate's hierarchy-resolved score (@section Score-sourcing hierarchy) is statistically indistinguishable from the anchor's own observed score, via the same score-only chi-squared outlier test evaluate_likelihoods() already uses (alpha, default 0.001). Prior-agnostic -- candidate_species_filter never gates this purpose. Requires model_params (for the per-species/global sigma the test needs); without it, no candidate is ever admitted under this purpose.

- "plausible_prior" (Purpose B -- plausible candidate admission): the candidate is on candidate_species_filter (or no filter was supplied at all) and its hierarchy-resolved score clears build_sequence_matrix()'s own max_dist sanity floor (default 0.25, ~75% identity) -- a much wider bar than Purpose A's, since local occurrence plausibility substitutes for some of the score-closeness Purpose A needs on its own.

- "both" when a candidate clears both gates (the wide gap is a superset of the tight one, so this never duplicates work -- the hierarchy score is resolved once and compared against both thresholds).

A candidate resolved via neither purpose (or with no evidence at all -- see @section Score-sourcing hierarchy's Level 0) is not restored as a hypothesis row, but -- when check_regional_overlap = TRUE -- may still be recorded via attr(result, "regional_unreferenced") (see @return) so it can compete through expand_unreferenced_hypotheses()'s generic borrowed-likelihood path instead.

No-score pathway (Rule 3 / best_only): when match_obj carries no usable score_col at all, there is no real evidence to source Purpose A/B from -- every same-genus congener (filtered by candidate_species_filter if supplied) is restored with a synthetic score: original rows get 1.0, restored rows get 1.0 - delta / 100. Pass the result to assign_scores(score_type = "direct") rather than the bivariate- normal pipeline. restoration_basis is NA for rows added this way (no purpose distinction applies without real score evidence).

#### Measured restored scores

A restored row's score is the QUERY's identity to the candidate whenever that can be measured: with sequence_col supplied, the query is aligned (pwalign::pairwiseAlignment(type = "local"), identity as pwalign::pid() PID1) to each of the candidate's references, and the best identity over references covering at least min_query_coverage of the query is used (restored_score_source = "measured"). A measured identity is then put on the observed scores' scale, the same rule for every marker: queries are aligned the same way to their own kept hits' references (every hit reference_df holds, up to 3,000 pairs), and (that identity - the observed score) is summarised per observed-score band (edges 75, 85, 90, 95, 98, 99.5). A band with fewer than 30 pairs is pooled into its upward neighbour; each measured score takes its band's median offset. Where the offset is flat the bands come out equal and this is a constant; where it slopes with identity they differ. A measured score outside the observed scores the offset was measured on takes the nearest band and is flagged (restored_offset_out_of_range), never with the below-floor flag. With fewer than 30 pairs in all the offset is 0 and flagged thin. The calibration is returned as attr(result, "measured_score_calibration") (offset, n, iqr, thin, bands, range, source). A measured score may exceed the observation's best observed score: a suppressed congener can genuinely match the query better than every hit the provider kept, since suppression does not follow identity.

Only when no reference clears the coverage rule (or no query sequence is available) does the score fall back to the hierarchy below, as an IMPUTATION (restored_score_source = "imputed"): min(ref_ref, anchor), where ref_ref is the hierarchy's identity. Every hierarchy level is REFERENCE-vs-REFERENCE identity -- including Level 4, whose pid is the candidate's reference aligned to the ANCHOR's reference; the query only locates the anchor range -- so used directly as the query's score it is a fair proxy only when the query matches its anchor almost exactly. An imputed score is asserted never to exceed the anchor; measured scores are not subject to that ceiling.

A restored score below the training floor 1 - max_dist (scores the likelihood model never trained on) is kept and flagged (restored_below_floor = TRUE). An observation whose scores are all NA has no anchor score to impute from: a candidate that cannot be measured there is not restored and is recorded in attr(result, "restoration_skipped") with reason "restored_no_anchor_score".

When reference_df carries a trim_path column (match_reference_region() output), only references placed on the query region are used, for measurement and for restoration alike; a candidate with no placed reference is not restored and is recorded in attr(result, "regional_unreferenced") with basis "no_placed_region_reference".

#### Score-sourcing hierarchy

Provides a real, evidence-grounded score for a restored candidate, rather than a flat anchor_score - delta imputation. Cheapest/most-certain first, stopping at the first level that resolves a candidate; aggregated by median, never max or a random pick, when more than one qualifying value exists at a level (max is an upward-biased order statistic -- a well-referenced species draws more pairs from the same underlying similarity distribution, inflating its expected max for reasons unrelated to true similarity).

- Level 0 precheck: does the anchor's own species have ANY seq_matrix representation at all (as id_x or id_y, against anything, not just this genus)? When it doesn't (e.g. its only references are out-of-range mitogenomes that never entered build_sequence_matrix()'s alignment), Levels 1-3 are all futile -- route straight to Level 4.

- Level 1 (free): direct accession-pair p_match lookup in seq_matrix -- the specific anchor accession vs. the specific candidate accession(s).

- Level 2 (free): any-accession species-pair lookup -- any reference accession of the anchor's species vs. any reference accession of the candidate species. Rescues a case where Level 1's specific accession is an unrepresentative outlier; it does not help when the missing pairs are genuinely outside max_dist.

- Level 3 (free), one level with an internal preference: a raw genus-wide median and the trained model's own genus-specific estimate both answer "typical congener divergence for this genus," at different levels of rigor, so they're tried as alternatives rather than strictly in sequence. Preferred: model_params$H2_Lookup$delta_shrunk (used when model_params has an entry for the anchor's genus) -- Empirical-Bayes-shrunk, matters most for thin-data genera, and keeps a restored row's imputed score consistent with the same estimate evaluate_likelihoods() already uses for that genus's H2 rows. Fallback: median p_match across all within-genus, cross-species pairs already present in seq_matrix, ignoring which two specific species are involved. Both require the Level 0 precheck to have passed.

- Level 4 (expensive, only when check_regional_overlap = TRUE): live pairwise alignment via the same Tier 1/2a/2b mechanism .check_regional_overlap() uses for the regional-overlap check, called with return_detail = TRUE to also read back a percent- identity score (pwalign::pid(), default PID1) from the same alignment object the position check already builds, at no extra alignment cost. A candidate whose position genuinely does not overlap the anchor's hit region is recorded via attr(result, "regional_unreferenced") rather than restored (see @return); one with literally no evidence either way (e.g. no usable sequence data, or skipped by the compute-budget mechanism) is recorded there too, distinguishable via its basis column ("regional_reject" vs. "no_reference_data").

#### Level 4 cost control

Level 4 is expensive: with the default candidate_species_filter = NULL, Purpose A's genus-wide sweep sends every congener of the anchor's genus to a live alignment against the anchor's reference (a 16kb mitogenome in the worst case). Two independent controls gate it, cheapest-decision first (see .worth_level4_check()/ .level4_attempt_allowed() for the derivation):

- candidate_species_filter (default gate): a candidate on the filter -- or any candidate, when no filter was supplied at all -- is always worth checking. Levels 1-3 remain completely unaffected by this filter; only Level 4 is gated.

- Floor-vs-documented ratio (fallback, only consulted for a candidate NOT on the filter): posterior_consensus()'s min_posterior filter (default 0.05) drops any hypothesis below ~1/19th of total posterior mass, and posterior is proportional to likelihood times prior, so a candidate's prior disadvantage alone can make it mathematically impossible to ever surface. Bounding a restored congener's likelihood at, at best, the anchor's own (L_candidate/L_anchor <= 1, a working assumption for a budget heuristic, not a correctness gate) gives: worth spending Level 4 budget only when R = P_anchor / P_candidate <= 19, where P_anchor/P_candidate are the two species' own occurrence-prior means at the observation's grid cell. R not being computable at all (either species absent from taxaexpect_priors at that grid cell, including an occurrence-implausible anchor) is treated the same as R > 19 -- skip.

max_level4_per_anchor (default 10L) is a separate, independent hard cap on top of both, insurance against a large/absent filter or a permissive ratio still admitting an unbounded number of candidates for one anchor.

### subset_local_database(fasta_path, taxa, rank, rank_system = c("family", "genus", "species"), taxonomy_file = NULL, taxonomy = NULL, max_n_bases = NULL, require_species = FALSE)

Subset a Large Local Reference Database by Taxon

Filters a large local FASTA + taxonomy file to a user-supplied taxon list, returning a 'reference_df' ready for 'build_sequence_matrix()' or 'train_likelihood_model()'. The taxonomy file is parsed first to identify matching sequence IDs; the FASTA is then streamed record-by-record, keeping only those IDs. Peak memory scales with the number of matching sequences, not the total database size, making this suitable for multi-gigabyte databases such as SILVA SSU, MIDORI2, or Greengenes2.

| Param | Required | Default | Doc |
|---|---|---|---|
| fasta_path | yes |  | Character. Path to the FASTA file. Plain text and .gz-compressed files are both supported. |
| taxa | yes |  | Character vector. Taxon names to retain (e.g., c("Fundulidae", "Gobiidae") for family-level filtering, or c("Fundulus", "Gambusia") for genus-level). |
| rank | yes |  | Character scalar. The rank at which taxa are defined; must be one of the values in rank_system (e.g., "genus", "family"). |
| rank_system | no | c("family", "genus", "species") | Character vector, coarse to fine (default c("family", "genus", "species")). Must include rank. |
| taxonomy_file | no | NULL | Character or NULL. Path to a 2-column taxonomy TSV (sequence ID TAB taxonomy string) in QIIME2/RESCRIPt, SILVA, MIDORI2, or GTDB format. Prefix-style (k__, d__) and positional semicolon formats are both auto-detected. Exactly one of taxonomy_file or taxonomy must be supplied. |
| taxonomy | no | NULL | Data frame or NULL. Pre-parsed taxonomy with a composite_id column plus one column per rank in rank_system. Exactly one of taxonomy or taxonomy_file must be supplied. |
| max_n_bases | no | NULL | Integer or NULL. Drop sequences longer than this many bases after extraction (useful for removing genomic contaminants from amplicon databases). |
| require_species | no | FALSE | Logical (default FALSE). If TRUE, drop sequences with NA in the species column. Requires "species" to be in rank_system. |

**Value:** A 'reference_df': a data frame with columns 'composite_id', plus one column per rank in 'rank_system', plus 'sequence'. Ready for 'build_sequence_matrix()' or 'write_reference_fasta()'.

#### Supported database formats

- SILVA: Download SILVA_*_SSURef_NR99.fasta.gz and the companion taxonomy TSV from https://www.arb-silva.de/download/. SILVA taxonomy strings use prefix-style (d__, p__, ) and are auto-detected. SILVA sequences span 16S/18S/23S rRNA and are the standard reference for microbial amplicon eDNA.

- PR2: Download the mothur-format taxonomy TSV (pr2_version_*_SSU_mothur.tax.gz) and its companion FASTA (pr2_version_*_SSU_mothur.fasta.gz) from https://github.com/pr2database/pr2database/releases. PR2 covers 18S rRNA with a protist/eukaryote focus. Its taxonomy strings use a fixed 9-level positional format (domain;supergroup;division; subdivision;class;order;family;genus;species, no prefix codes) -- auto-detected by field count (confirmed against a real v5.1.1 release; see .pr2_hierarchy's roxygen for detail). Two real quirks worth knowing before filtering: plastid-derived sequences suffix every level with :plas (preserved as-is, not stripped, since it's a real ancestry signal); and species-level values are underscore-joined and often unresolved placeholder labels (e.g. Rozellomycota_XXX_sp.) rather than clean binomials.

- MIDORI2: Download the FASTA (MIDORI2_UNIQ_NUC_*_QIIME.fasta) and its companion _taxon.tsv from https://www.reference-midori.info/. MIDORI2 covers COI and a range of nuclear markers for metazoan eDNA; the full COI release is ~4 GB. Its license is reported as CC-BY-NC in secondary sources (unconfirmed on the primary site) -- this may be in tension with this ecosystem's CC0/USGS public-domain policy. This function never fetches, bundles, or redistributes MIDORI2 data itself (it only filters a copy the user already downloaded), so it carries no license obligation on its own -- but the license question is real for the USER: do not redistribute any MIDORI2-derived reference_df/FASTA output beyond local model training until the license is confirmed directly with the MIDORI2 maintainers.

- GTDB: GTDB taxonomy differs from NCBI for bacteria and archaea. Export GTDB-formatted 16S sequences + taxonomy via QIIME 2 (qiime tools export) or download pre-built QIIME2 classifiers and extract the FASTA + TSV. GTDB taxonomy strings use d__/p__ prefix-style and are auto-detected.

- Greengenes2: Available as QIIME 2 artifacts from http://ftp.microbio.me/greengenes_release/. Export the FASTA + taxonomy TSV with qiime tools export before calling this function. Greengenes2 (2022+) uses GTDB-derived taxonomy.

- RDP: Download FASTA + lineage file from https://rdp.cme.msu.edu/misc/resources.jsp. RDP lineage files are tab-delimited with a multi-column hierarchy; reformat to a 2-column (ID TAB taxonomy string) TSV before use, or load as a data frame and pass via taxonomy.

- CRUX or custom FASTA: If you already have a data frame of taxonomy (e.g., from read_reference_fasta()), pass it via taxonomy instead of taxonomy_file. For CRABS internal-format files use read_crabs_output() directly.

#### ID matching

FASTA header IDs are extracted as the first whitespace-delimited token after > (e.g., AB353770.1 from >AB353770.1 Bacteria;...). Version suffixes (.1, .2) are stripped from taxonomy TSV IDs before matching, consistent with the behaviour of .parse_taxonomy_tsv(). If IDs still fail to match after stripping, inspect the first few lines of both files for format discrepancies.

### suggest_unreferenced_species(match_df, context = NULL, barcode_term = "COI", llm_fn = NULL, data_type, reference_species = NULL, expand_to_family = FALSE, max_date = NULL, min_len = NULL, max_len = NULL, taxa_per_call = 30L, pause_seconds = 1, ncbi_api_key = NULL, verbose = FALSE)

Suggest Unreferenced Species Using an LLM

A fast, LLM-first alternative to 'audit_barcode_coverage()' for unreferenced species detection. An *unreferenced species* is a described taxon that shares a genus (or family, with 'expand_to_family = TRUE') with a scored reference match candidate but is absent from the reference dataset. The definition of "absent" depends on 'data_type': no NCBI barcode sequence (eDNA), or not in the model's training species list (acoustic / image).

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Canonical match object from TaxaMatch (or equivalent). Required column: taxon_name. Optional but strongly recommended: genus (if absent, derived from taxon_name). A genus value that does not look like a plausible genus name (a single capitalised word) is dropped with a message() rather than reaching the LLM prompt verbatim. Required for expand_to_family = TRUE: family. |
| context | no | NULL | Optional named list or single-row data frame with location / habitat context for the LLM. Recognised fields: ecoregion, lat, lon, date, habitat. NULL (default) sends no context. |
| barcode_term | no | "COI" | Character scalar or vector. One or more marker search terms (e.g. "12S", c("12S", "MiFish")). Multiple terms are OR-ed. Default "COI". |
| llm_fn | no | NULL | Function or NULL. Provider function following the TaxaTools llm_fn pattern: accepts a single character string prompt and returns a single character string response. Default NULL resolves to getOption("TaxaID.llm_fn") when set, otherwise TaxaTools::call_api (requires TaxaTools). |
| data_type | yes |  | Character. One of "eDNA", "acoustic", or "image". No default -- the caller must state the signal. Controls how "unreferenced" is defined: "eDNA": unreferenced = no NCBI barcode sequence for the target marker. Uses NCBI nucleotide count queries. "acoustic": unreferenced = absent from the acoustic model training set (e.g., not in BirdNET's species list). Requires reference_species. "image": unreferenced = absent from the image classifier training set. Requires reference_species. |
| reference_species | no | NULL | Character vector or NULL. Required when data_type is "acoustic" or "image". The known-species list for the acoustic or image model (e.g., the BirdNET species list). Species absent from this vector are classified as unreferenced. Ignored when data_type = "eDNA". Default NULL. |
| expand_to_family | no | FALSE | Logical. If TRUE, genera for which the LLM returned zero plausible species trigger a second LLM call asking for plausible species in OTHER genera of the same family. These family-level unreferenced species fill the role of TaxaLikely's H3 (unreferenced genus) hypothesis with named species. Requires a family column in match_df. Default FALSE. |
| max_date | no | NULL | Optional character scalar. Restricts unreferenced species detection to sequences present in NCBI on or before this date. Format: "YYYY", "YYYY/MM", or "YYYY/MM/DD". NULL uses the current state of GenBank. |
| min_len | no | NULL | Integer or NULL. Minimum sequence length (SLEN filter). NULL uses a barcode-specific default. |
| max_len | no | NULL | Integer or NULL. Maximum sequence length. NULL uses the barcode-specific default. |
| taxa_per_call | no | 30L | Integer >= 1. Maximum genera per LLM call. Default 30. |
| pause_seconds | no | 1 | Numeric. Seconds to pause between LLM calls. Default 1. |
| ncbi_api_key | no | NULL | Optional NCBI API key. Raises rate limit from 3 to 10 requests per second. Can also be set via the ENTREZ_KEY environment variable. |
| verbose | no | FALSE | Logical. If TRUE, prints each prompt and raw LLM response. Default FALSE. |

**Value:** A character vector of unreferenced species names with class 'c("unreferenced_species_result", "character")'. 'length()' returns the total number of unreferenced species (congener + family-level combined). Pass directly to 'TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...)'.

#### Details

##### Algorithm

- Genus-level LLM call: For each genus in match_df, the LLM lists all biogeographically plausible species. Genera are batched by taxa_per_call.

- Skip-list removal: Species already in match_df have reference sequences by definition and are removed from the candidate list.

- NCBI barcode count: For each remaining plausible species, rentrez::entrez_search() is called with retmax = 0 (count only). Count = 0 or persistent failure (NA after 3 retries) -> unreferenced.

- Family-level expansion (optional): When expand_to_family = TRUE, genera for which the LLM found zero plausible species trigger a second LLM call asking for plausible species in other genera of the same family. Those candidates go through the same NCBI count step. Requires a family column in match_df.

##### Return value

The visible return is a character vector of unreferenced species names of class c("unreferenced_species_result", "character"), suitable for direct use as TaxaAssign::assign_taxa_llm(unreferenced_taxa = ...). assign_taxa_llm automatically detects the unreferenced_family attribute and activates family-level unreferenced species insertion when it is present.

Additional details are attached as attributes:

- attr(result, "plausible") -- all LLM-generated species (genus-level) before the NCBI filter (character vector).

- attr(result, "census") -- data frame with one row per genus: genus, plausible_count, ncbi_count, unreferenced_count.

- attr(result, "unreferenced_family") -- named character vector mapping each family-level unreferenced species to its family name. NULL when expand_to_family = FALSE or when no family-level unreferenced species were found.

- attr(result, "family_census") -- data frame with one row per expanded family: family, plausible_count, ncbi_count, unreferenced_count. NULL when expand_to_family = FALSE.

### taxalikely_clear_cache(cache_dir = tools::R_user_dir("TaxaLikely", "cache"), older_than_days = NULL, dry_run = FALSE, force = FALSE)

Report and clear TaxaLikely's on-disk cache

'fetch_ncbi_reference_sequences()' caches one small file per (taxon, barcode_term, length window, date range, out-of-range settings, rank_system) combination it has ever been asked for, plus one file per accession under 'fasta/'; 'audit_barcode_coverage()' caches one checkpoint per (rank, marker, params) combination it has run. All cache under a persistent, user-level directory and none expires automatically. This function reports how much space the cache is using and, unless 'dry_run = TRUE', removes it.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaLikely", "cache") | Character. Cache directory to inspect/clear. Defaults to tools::R_user_dir("TaxaLikely", "cache"), the same default used by fetch_ncbi_reference_sequences()/audit_barcode_coverage(). |
| older_than_days | no | NULL | Numeric or NULL. When supplied, only files older than this many days (by modification time) are targeted. NULL (default) targets every recognized cache file in cache_dir. |
| dry_run | no | FALSE | Logical. If TRUE, reports what would be removed without removing anything. Default FALSE. |
| force | no | FALSE | Logical (default FALSE). Pass TRUE to clear a cache_dir that holds file(s) matching none of the recognized cache patterns -- see list_cache_files. |

**Value:** Invisibly, a data frame of the targeted files ('path', 'size_mb', 'mtime'), possibly zero rows.

#### Details

It is the blunt instrument: it targets EVERY recognized cache file, whether or not a later call could still hit it -- including generations superseded by a cache-key widening (45% of the meta store on a real cache directory). The automatic write-path eviction in fetch_ncbi_reference_sequences() removes only those provably-dead files, scoped to the taxon just rewritten, on every fetch.

### train_likelihood_model(raw_df, rank_system = NULL, score_bounds = NULL, min_observed_sigma = NULL, prior_weight = 10, use_hierarchy = TRUE, anchor_perfect = TRUE, logit_epsilon = 1e-04, max_gap_ceiling = NULL, score_transform = "logit", min_pair_coverage = 0.8, shrinkage = c("empirical_bayes", "fixed"))

Train the hierarchical likelihood model on reference-vs-reference scores

Fits an Empirical Bayes model using pairwise within-species match scores (from 'build_sequence_matrix()') to learn species-specific score distributions. Per-species parameters are shrunk toward a global mean, with shrinkage strength inversely proportional to the number of observations for that species. Optionally uses 'lme4' random intercepts per taxonomic rank for more robust estimation.

| Param | Required | Default | Doc |
|---|---|---|---|
| raw_df | yes |  | Data frame of pairwise match scores, as returned by build_sequence_matrix(). Passed through .prep_training_data(). |
| rank_system | no | NULL | Character vector of rank names, coarse to fine (e.g., c("family", "genus", "species")). Default NULL auto-detects from the .x-suffixed columns in raw_df. |
| score_bounds | no | NULL | Optional c(min, max) for score normalization. |
| min_observed_sigma | no | NULL | Numeric or NULL (default). Numerical floor on the score variances (pooled and per species). NULL resolves to 0.01 transform units squared (0.01 in logit space, rescaled for "sqrt_mismatch"), a guard against degenerate zero-variance estimates, not a noise model: the spread is estimated from the reference pairs, per-species estimates are shrunk toward the pooled one, and the extra scatter of field queries is measured by calibrate_query_noise(). A floor of 1.0 unit^2 was measured at 5-8x the real within-species variance on 12S, 18S and COI, flattening every likelihood ratio. |
| prior_weight | no | 10 | Numeric. Equivalent pseudo-sample size for Empirical Bayes shrinkage toward the global mean. Controls how strongly species-specific estimates are regularized. A value of 10 means each species estimate is pulled toward the global mean as if 10 additional observations at the global mean had been added. Higher values produce more conservative (less species-specific) estimates; lower values trust per-species data more but risk overfitting for species with few references. Default 10.0. |
| use_hierarchy | no | TRUE | Logical (default TRUE). If TRUE and lme4 is available, fits random intercepts per rank level to stabilize estimates across the taxonomic hierarchy. |
| anchor_perfect | no | TRUE | Logical (default TRUE). If TRUE, injects synthetic perfect-match observations into the H1 training data to prevent the perfection penalty (see section below). |
| logit_epsilon | no | 1e-04 | Numeric. Logit-clipping value (default 1e-4). Used only when score_transform = "logit". |
| max_gap_ceiling | no | NULL | Numeric or NULL (default). Gap cap. NULL resolves to 5.0 for score_transform = "logit" (roughly the gap between 99.3% and 50% identity, in logit units) or 0.6234 for "sqrt_mismatch" (the same 99.3%-vs-50% reference gap on that scale) -- prevents extreme outliers from dominating model estimates either way. |
| score_transform | no | "logit" | Character, "logit" (default) or "sqrt_mismatch". The scale H1/H2/H3 are all modeled on -- must be shared across all three hypotheses, since they are compared via density ratios at the same observed point (a valid likelihood ratio requires one consistent scale; mixing transforms across hypotheses would need an explicit change-of-variables correction that this package does not implement). "logit" (log(p/(1-p))) is a standard scale. "sqrt_mismatch" (-sqrt(1-p)) exists because real 12S congener data showed "logit" gives a genuinely backwards answer for one of the package's more novel claims: whether a genus's species are hard to tell apart (small, consistent divergence) or easy to tell apart (larger, more variable divergence). On the raw match-proportion scale, tight genera show lower congener-score variance, as expected -- but under "logit", this can reverse sign, because nearly all real barcode matches sit close to 100% identity, exactly where logit's derivative diverges fastest. "sqrt_mismatch" treats divergence as a rare-event count (few mismatches out of many aligned bases -- the regime real data is actually in), for which square-root is the classical variance-stabilizing transform; it recovers the correct qualitative ordering where "logit" does not. See evaluate_likelihoods()'s own documentation for the full empirical derivation, including why several other standard transforms (probit, complementary log-log) were checked and rejected. "sqrt_mismatch" is bounded to [-1, 0] rather than unbounded like "logit" -- a Gaussian fit to it is technically an approximation for that reason, but a mild one in practice, since real observations concentrate near 0 (good matches), far from the -1 boundary. Not yet ported to this scale: calibrate_query_noise() and evaluate_likelihoods()'s evidence_col/min_coverage mechanisms all assume "logit" internally and will error rather than silently produce wrong numbers if combined with a "sqrt_mismatch"-trained model. |
| min_pair_coverage | no | 0.8 | Numeric in (0, 1] or NULL (default 0.8). The alignment-coverage floor a reference-vs-reference pair must meet before it may DEFINE a reference's best foreign match, best congener match, or best conspecific match (coverage column from build_sequence_matrix()). Must equal the coverage floor the match object was built under -- TaxaMatch::blast_sequences(min_query_coverage = 80) is 0.8 here -- so that training and inference see the same pair population; evaluate_likelihoods()'s check against the match object is one-directional -- it warns only when the match object admits LOWER coverage than this model's own floor (a 0.01 tolerance), never the other way around. This is NOT a data filter: no pair is removed from the data and no species is ever dropped (a reference with no qualifying conspecific pair falls back to its best one). NULL disables the floor; a raw_df without a coverage column skips it with a message. See the "Alignment-coverage floor" section. |
| shrinkage | no | c("empirical_bayes", "fixed") | "empirical_bayes" (default) or "fixed". How each species' H1 mean score and mean gap are shrunk toward the global mean. "fixed" is the original N / (N + prior_weight) weight. "empirical_bayes" estimates the real between-species variance of the means (tau^2, method of moments, per dimension) and weights each species by tau^2 / (tau^2 + sigma^2 / N): no signal beyond noise collapses every species to the global mean, real signal lets well-referenced species keep more of their own. The estimate is reported in Stats$tau2_score/Stats$tau2_gap and the per-species weights in H1_Lookup$shrink_w_score/shrink_w_gap. Variance shrinkage always uses the fixed weight. Needs at least 3 species; otherwise falls back to "fixed" with a message. |

**Value:** A named list (class '"taxa_model_params"') with slots: 'H1_Lookup' Data frame with per-species parameters: 'lookup_key', 'rank', 'mu_score', 'mu_gap', 'sigma_score', 'n_obs_species' (number of within-species reference sequences trained on - used by 'evaluate_likelihoods()' to weight the Monte Carlo uncertainty of the trained mean; see that function's own documentation). 'H1_Global_Mu' Named numeric vector: 'score_logit', 'gap_logit'. 'H1_Sigma' 2x2 covariance matrix for the global H1 distribution. 'Score_Transform' Character, '"logit"' or '"sqrt_mismatch"' - the scale this model's H1/H2/H3 parameters were fit on. Read automatically by 'evaluate_likelihoods()'; callers should not need to track or re-supply it. 'H2' List with 'delta' and 'sigma' for the missing-species hypothesis (pooled across all genera). 'H3' List with 'delta' and 'sigma' for the missing-genus hypothesis. 'H2_Lookup' Data frame (or 'NULL') with per-genus 'H2' delta and variance estimates: 'genus', 'n_pairs', 'delta_shrunk', 'var_shrunk'. See "Per-genus delta shrinkage" section below. 'Confusion_Risk_Curves' List (or 'NULL') of genus-/family-equal- weighted, Empirical-Bayes-shrunk per-rank score curves, read by 'evaluate_likelihoods()' to compute its 'species_confusion_risk'/ 'genus_confusion_risk'/'family_confusion_risk' output columns - a model-independent, score-only diagnostic of the risk that the raw match score is equally well explained by a confusable congener/ confamilial/cross-family relative at the rank a hypothesis resolved to, distinct from this model's own trained bivariate-normal likelihood. 'NULL' when 'rank_system' has fewer than 2 levels or the required taxonomy columns aren't usable ('species_confusion_risk'/ 'genus_confusion_risk'/'family_confusion_risk' are then simply 'NA', never an error). See '.compute_rank_score_curves()''s own documentation for the exact structure, and 'compute_rank_thresholds()' for the sibling function that derives 'TaxaAssign::score_consensus()''s 'rank_thresholds' from the same underlying curves. 'Stats' List of diagnostics: 'AIC_Score' From the 'lme4' hierarchy fit, when it succeeded; 'NA' otherwise. 'n_species' Number of species with at least one H1 (within-species) training pair. 'n_singletons' Number of reference sequences with no within-species neighbour, trained via the '"Singleton"' pathway (see '.prep_training_data()'). 'n_anchors' Number of synthetic perfect-match pseudo- observations injected via 'anchor_perfect'; '0' when disabled. 'n_h1_pooled' Total sequences behind the global H1 mean (informational only; NOT used as the Monte Carlo uncertainty fallback - see 'prior_weight' below). 'n_h2_pooled' Foreign-match count behind the pooled global 'H2' delta, 'NA' when too few foreign matches existed to estimate one (also informational only). 'prior_weight' The same value passed to this call - what 'evaluate_likelihoods()' actually uses as the equivalent sample size for candidates with no species/genus-specific reference data at all: the true pooled sample size ('n_h1_pooled'/'n_h2_pooled') reflects how well the GLOBAL average is known, not how confidently that average applies to a candidate we have zero direct data for, so using it directly would understate uncertainty exactly where it should be largest. 'shrinkage' '"empirical_bayes"' or '"fixed"' - which shrinkage-weight formula was actually used for the per-species H1 means (see the 'shrinkage' parameter). 'tau2_score', 'tau2_gap' Method-of-moments estimates of the between-species variance of the H1 score/gap means (used only under 'shrinkage = "empirical_bayes"'; both 'NA' under '"fixed"'). These carry NO standard error: with K non-singleton species, the sampling SD of the between-species variance estimate is roughly 'var * sqrt(2/(K-1))', so a true tau/sigma up to about 0.2-0.3 is statistically indistinguishable from 0 at K ~= 40 and gets truncated to exactly 0. A value of '0' therefore means "not detectable at this species count," not "genuinely absent." 'min_pair_coverage' The coverage floor actually applied (see the 'min_pair_coverage' parameter), or 'NA_real_' when 'raw_df' carried no 'coverage' column and the floor was skipped entirely. 'n_self_fallback' Number of references whose best conspecific pair fell below 'min_pair_coverage', so they fell back to their best conspecific pair regardless - a reference is never dropped from training by the floor. 'n_foreign_unqualified' Number of references with no qualifying foreign pair clearing 'min_pair_coverage', routed to the noise-floor global rather than an unfiltered (and potentially coverage-inflated) maximum. 'mlr_violations' Character vector of species names failing the monotone-likelihood-ratio check against their genus's H2 alternative (see '.check_score_ratio_monotonicity()'); empty (length 0) when none violate it. 'max_ceiling_z', 'max_ceiling_z_species' The largest floored-sigma distance, across every trained species, between a perfect match and that species' own fitted score mean, and which species it belongs to. 'h1_bimodality' The result of running '.bimodality_check()' on this model's own real H1 training scores (raw percent identity, real within-species pairs only - computed BEFORE any 'anchor_perfect' pseudo-observations are appended, so a synthetic anchor spike can never manufacture a false second mode). A list with 'n', 'bic_1', 'bic_2', 'delta_bic', 'weights', 'means', 'sds', 'quantum' (the estimated identity-per-mismatch spacing, or 'NA' when the scores don't look discretely comb-shaped), 'flag', and 'explanation' - see that function's own docs and 'calibrate_query_noise()''s "Bimodality diagnostic" and "Percent identity is discrete, not continuous" @sections for the full mechanism and thresholds. This function only RECORDS the result on the model, it does not warn - see @section H1 bimodality (recorded, not warned) below.

#### Model structure

For each candidate hypothesis the model uses a 2-dimensional multivariate normal distribution over (score_logit, gap_logit):

- H1 (known species): species-specific mean with shrinkage; global covariance matrix.

- H2 (missing species): H1 mean shifted left by H2$delta -- approximately what a sister species looks like. H2$delta is a single value pooled across every genus in the training set; where a genus has real congener pairs in the reference, H2_Lookup provides a genus-specific delta that evaluate_likelihoods() prefers when available (see "Per-genus delta shrinkage").

- H3 (missing genus): H1 mean shifted further left by H3$delta.

#### Memory

The per-reference training passes (each reference's best foreign, congener, confamilial and ring match, its gap draws, its best conspecific pair, and the confusion-risk curves' per-reference best match) are computed in blocks of whole references, so their temporaries scale with the block rather than the whole pair table. The output is identical for any block size. The rate curves by species, genus and family span references and are computed once, on the combined per-reference results. The species pair counts (N_Obs) are counted per block and summed, which is exact because row counts add over disjoint blocks. Block size: options(TaxaLikely.train_block_ids =), references per block, default 5000.

#### Marker validation scope

The continuous bivariate-normal form (as opposed to a discrete "100% match or nothing" rule) was validated empirically for the 12S and 18S markers only: 100% rules were unreliable at the congeneric level, and the bivariate-normal form captured the real score distribution well for those two markers. Nothing in this function checks that the same form fits a different marker (e.g. COI, 16S, cytb, rbcL, matK, trnL, all trainable here via trim_to_amplicon()) before fitting it. Run the seq_matrix_score_distribution.R diagnostic (TaxaID_dev repository) on build_sequence_matrix() output for a new marker before trusting this model there; it checks logit-normality and the H1/H2 spike ratio, the two properties the Gaussian form assumes.

#### Per-genus delta shrinkage

The pooled H2$delta treats every genus identically, a poor approximation for genera whose real congeneric divergence is far from the training-set average, most consequentially cryptic species complexes, where true divergence is much smaller than the pooled estimate and the pooled delta overstates confidence in the known-species hypothesis. Where a genus has at least one real congener pair in the reference database, H2_Lookup stores a genus-specific delta shrunk toward the pooled value by n_pairs / (n_pairs + prior_weight) (the same Empirical Bayes form used for per-species means). A genus with only one referenced species (no congener pairs) gets no H2_Lookup row and falls back to the pooled H2$delta unchanged; local divergence cannot be estimated from a single species and none is invented.

This says nothing about whether an unreferenced congener is plausible in the first place (a prior-side question, answered by TaxaExpect from occurrence/richness data), only about how far its likelihood should be shifted from a known match if one exists. Nor does it address a query whose true relatives are absent from the reference for reasons unrelated to sequence divergence (e.g. an unreferenced acoustic or visual mimic in the acoustic and image pathways, where evidence similarity need not track phylogeny); see inst/TaxaLikely_supplemental_methods.md.

#### Unsequenced-genus likelihood (H3)

H3 is the hypothesis that the query comes from a genus of the anchor's family that has no reference sequence. Its score distribution is measured the way H2's is: for each reference, its best match to a species of another genus in the same family (rank_code_c, conventionally family). The mean is family-equal-weighted (mean of family means), so one heavily sequenced family cannot set it, and the shift is kept at least as large as the pooled H2 shift so an unsequenced genus is never assumed to match better than an unsequenced congener. The variance uses the same family-equal weights (mean within-family variance plus the variance of family means); depending on the marker this can sharpen or widen H3, so species calls can become somewhat more or less confident. With fewer than 3 families supplying such matches, the shift falls back to the H2 shift plus 2.0 transform units; Stats$h3_source records which was used.

Two sampling effects bear on the measured value, in opposite directions. Pairs below build_sequence_matrix()'s identity floor (max_dist) are never stored, so a very poor confamilial match cannot be observed, which pushes the estimate up; Stats$h3_share_near_floor reports how much of the pool sits in the lowest 5 percent of its observed range (3 to 8 percent on real 12S, 18S and COI data, so this effect is small). And under build_sequence_matrix(by_genus = TRUE) each genus is aligned against a random sample of other genera's single representatives, so most confamilial pairs are never computed and the stored best is the best against one sampled genus rather than every referenced genus of the family. That pushes the estimate down. The measured similarity is therefore a lower bound: an unsequenced genus probably matches more closely than H3 assumes, so H3 still loses somewhat too easily to a referenced candidate and calls keep some residual overconfidence.

#### Pseudo-data anchoring

When anchor_perfect = TRUE, synthetic "perfect match" observations are injected into the H1 training data before fitting the global mean. This softens the perfection penalty, a pathology where a 100% match receives a lower likelihood than the training mean (e.g., 98.5%) because the Gaussian density peaks at the mean, by nudging the global (pooled) mean upward, diluted by however much real training data exists. It does not force any individual species' own H1_Lookup$mu_score to the ceiling (the anchor rows are excluded from per-species estimation before shrinkage) and does not, on its own, guarantee a monotonically increasing density toward 100% for any given species; see "Non-monotonic score->likelihood shape" for the property the model actually needs (and checks automatically). The number of anchor points is 10% of the H1 training rows (minimum 5), enough to nudge the pooled mean without overwhelming real data; a species with abundant real data is essentially unaffected.

Adding n0 synthetic rows at a target value is mathematically equivalent to a Normal(target, sigma^2/n0) prior on the mean with its closed-form posterior mean, the same w = N/(N+prior_weight) Empirical Bayes shrinkage form used throughout this model (see prior_weight), so the correction runs on the same estimation machinery as everything else.

#### Non-monotonic score->likelihood shape

A trained species' H1 density is a Gaussian (or bivariate normal, jointly with gap) on the transformed score, and a Gaussian is unimodal by construction: it peaks at that species' own fitted mu_score, not necessarily at the transformed value of a perfect (100%) match. Since mu_score is estimated from real reference-pair comparisons (essentially never exactly 100% identical even for the correct species, owing to intraspecific variation and sequencing/assembly noise) and real query-time scores run below the training-only mean on top of that (see calibrate_query_noise()), it is normal for a species' H1 density to peak at an intermediate score and decline as score approaches 100%. This is not itself a sign of overfitting or a bug.

What matters for a Bayesian classifier is whether the H1-vs-H2 likelihood ratio stays monotone at the ceiling, i.e. whether a better score is ever weaker evidence for the known-species hypothesis than for the missing-species alternative. Two Gaussians with different means and variances can cross twice, so this is checked directly at the end of training via an internal .check_score_ratio_monotonicity(), using the same inference-time sigma floor evaluate_likelihoods() applies. A warning() is raised if any species' ratio turns over before the ceiling, or if any species' perfect-match point sits more than 2 floored standard deviations from its own fitted mean; both symptoms are recorded in Stats (mlr_violations and max_ceiling_z).

Under score_transform = "logit", the transformed value of a perfect match is not fixed by real data but set by logit_epsilon (a numerical-hygiene constant), and the default sits only about one order of magnitude from a value that would make every perfect match implausible under every species' own fitted distribution. "sqrt_mismatch" has no such fragility (a perfect match maps to exactly 0, the finite edge of its range, with no free parameter) and is the more robust choice for any new training run near this boundary.

#### Alignment-coverage floor on pair selection

The H1 gap feature is score - max_foreign_score, and max_foreign_score is taken over every cross-species pair a reference has. A pairwise alignment between a short deposit and an unrelated sequence can be 100% identical over a few percent of the sequence and then be the "best foreign match", pushing most training gaps to <= 0 and the global expected gap negative. At inference every BLAST candidate has query coverage >= 80, so a perfect match with a real positive gap would read as atypical while a 96% match with a negative gap read as typical, producing spurious H1 near-ties.

min_pair_coverage restricts which pair may define the foreign, congener and conspecific maxima to pairs at or above the inference-side floor. It is train/inference distribution matching for one feature, not a data quality filter: it removes no pair and drops no species.

#### No built-in reference-quality screening

This function does NOT screen raw_df for mislabeled/contaminated reference accessions before fitting; it trains on exactly what it is given. Screen with TaxaMatch::corroborate_references_locally() + TaxaMatch::evaluate_reference_accessions() directly on reference_df before it reaches build_sequence_matrix(), and exclude any accession that evaluate_reference_accessions()/score_reference_labels() resolves to reference_action == "remove" from reference_df (or from raw_df by id_x/id_y) before calling this function. There is no parameter here to pass a bad-accession list through.

#### H1 bimodality (recorded, not warned)

Stats$h1_bimodality runs the same two-component-normal-vs-BIC check calibrate_query_noise() uses (see its "Bimodality diagnostic" and "Percent identity is discrete, not continuous" sections for the method and thresholds) on this model's own real H1 training scores, so a saved lik_model carries the evidence whether or not calibrate_query_noise() is ever called on it. Percent identity is discrete, not continuous, and every reference-based dataset has a structural spike at or near 100% identity (each reference matching itself or an identical duplicate deposit); that spike alone is not evidence of a second population. .bimodality_check() therefore estimates the identity quantum from the data and smooths over it before fitting, requires the minority component to hold real mass, and requires the two fitted means to be separated by more than a few quanta.

H1 training pairs come from build_sequence_matrix()'s reference-vs-reference alignments, whose length varies pair to pair, so their quantum grid is a mixture of many overlaid quanta and the estimated quantum is much finer than for the single-query-length scores calibrate_query_noise() sees. The quanta-separation guard therefore does little here, and Stats$h1_bimodality$flag can read TRUE for training data that simply has this "spike at 100" shape; a very small quantum is the visible signal that a flagged split may be this artifact.

This function deliberately does NOT warning() on a flag: calibrate_query_noise() is where a single offset/line is actually applied to inference-time scores, so the warning belongs there. This is a diagnostic only: it never changes H1's fitted mean/sigma, and training is never refused when the flag is TRUE. The remedy for genuinely mixed sequencing platforms or markers is to train and calibrate them separately; this package does not do that for you.

### trim_to_amplicon(reference_df, primer_fwd = NULL, primer_rev = NULL, barcode_term = NULL, min_len = NULL, max_len = NULL, max_mismatch_rate = 0.15, verbose = TRUE)

Extract the amplicon region from over-length reference sequences (in-silico PCR)

GenBank mixes short, purpose-cut barcode submissions with much longer sequences (full mitochondrial genomes, whole-genome scaffolds, full ribosomal operons) that happen to contain the target locus somewhere inside them. 'build_sequence_matrix()''s 'min_seq_len'/'max_seq_len' filter excludes these outright - correct for well-sampled species, but for a poorly-sampled species whose only GenBank record is over-length, exclusion throws away the only genuine reference data available for it.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with at least composite_id and sequence columns (the same object produced by fetch_ncbi_reference_sequences() / read_reference_fasta() and consumed by build_sequence_matrix()). |
| primer_fwd | no | NULL | Character scalars: forward and reverse primer sequences, 5' to 3', IUPAC-degenerate bases allowed. Supply both, or neither (to look up barcode_term in TaxaTools::barcode_primer_defaults instead). |
| primer_rev | no | NULL | Character scalars: forward and reverse primer sequences, 5' to 3', IUPAC-degenerate bases allowed. Supply both, or neither (to look up barcode_term in TaxaTools::barcode_primer_defaults instead). |
| barcode_term | no | NULL | Character scalar naming a registered primer set (e.g. "MiFishU"), resolved via TaxaTools::resolve_barcode_primers(). Also used to auto-resolve min_len/max_len via TaxaTools::resolve_barcode_lengths() when those are not supplied directly. |
| min_len | no | NULL | Integer. Governs which sequences are left untouched as already barcode-length (<= max_len) versus checked for the amplicon region. Default NULL auto-resolves both from barcode_term via TaxaTools::resolve_barcode_lengths() -- in that case, the FINAL plausibility check on a matched amplicon span instead uses a bound derived from the registered primer pair's own amplicon_range (the literature-reported variable-region length) plus each primer's length, since min_len/max_len alone describe a general marker-length window, not a primer-inclusive matched span (reusing them directly would reject every genuine MiFish-U hit as "implausible" by ~11bp). If you supply min_len/max_len explicitly, that choice is used as-is for BOTH the over-length decision and the final plausibility check. |
| max_len | no | NULL | Integer. Governs which sequences are left untouched as already barcode-length (<= max_len) versus checked for the amplicon region. Default NULL auto-resolves both from barcode_term via TaxaTools::resolve_barcode_lengths() -- in that case, the FINAL plausibility check on a matched amplicon span instead uses a bound derived from the registered primer pair's own amplicon_range (the literature-reported variable-region length) plus each primer's length, since min_len/max_len alone describe a general marker-length window, not a primer-inclusive matched span (reusing them directly would reject every genuine MiFish-U hit as "implausible" by ~11bp). If you supply min_len/max_len explicitly, that choice is used as-is for BOTH the over-length decision and the final plausibility check. |
| max_mismatch_rate | no | 0.15 | Numeric in [0, 1) (default 0.15). Maximum fraction of primer positions allowed to mismatch the sequence at the binding site (rounded down to an integer count of bases per primer). Accounts for real SNP variation at primer-binding sites; degenerate IUPAC bases in the primer itself are handled separately and do not count as mismatches when compatible with the sequence base. |
| verbose | no | TRUE | Logical (default TRUE). Print progress/summary messages. |

**Value:** 'reference_df' with 'sequence' updated in place for successfully trimmed rows, plus two new columns: 'amplicon_trimmed' Logical. 'TRUE' if this row's sequence was replaced with an extracted amplicon. 'amplicon_trim_note' Character. One of '"within_length_range_no_trim_needed"', '"extracted_via_primer_match_sense_strand"', '"extracted_via_primer_match_antisense_strand"', '"primers_not_found_or_implausible_span"', '"non_iupac_dna_skipped"', '"invalid_dna_string"', or '"missing_sequence"'.

#### Details

trim_to_amplicon() locates the forward and reverse primer-binding sites within each over-length sequence and extracts just the amplicon between them -- the same result a real PCR reaction targeting that marker would have produced -- so the sequence can still contribute real same-species training data instead of being dropped.

Sequences already within [min_len, max_len] are left completely unchanged (most purpose-cut barcode submissions have already had their primers trimmed off at deposition, so attempting primer matching on them would often fail even though the sequence is perfectly usable). Only sequences longer than max_len are searched for primer sites.

#### Failure mode

When a primer site cannot be found within tolerance on either strand, or the two matched sites imply an implausible amplicon length (outside [min_len, max_len] -- e.g. a spurious match pairing far from the real target), the sequence is left unchanged (still over-length) and flagged in amplicon_trim_note. It will still be excluded by build_sequence_matrix()'s own length filter, exactly as it would be without ever calling this function -- this function only ever adds sequences that would otherwise be lost, never removes ones that would otherwise be kept.

#### Pipeline placement

Standalone stage, run by the caller between fetch_ncbi_reference_sequences()/read_reference_fasta() and build_sequence_matrix():


```

reference_df <- fetch_ncbi_reference_sequences(...) reference_df <- trim_to_amplicon(reference_df, barcode_term = "MiFishU") ref_matrix <- build_sequence_matrix(reference_df, ...) ```

#### Primer source and scope

Primer sequences come from TaxaTools::barcode_primer_defaults, populated only for primer sets directly verified against their primary publication -- currently MiFish-U and MiFish-E (12S; Miya et al. 2015). For any other marker, either supply primer_fwd/primer_rev directly (from your own wet-lab protocol or the relevant primer paper), or pre-trim sequences to the amplicon region with the external CRABS tool (https://github.com/gjeunen/reference_database_creator) before calling build_sequence_matrix() -- see read_crabs_output(). This function deliberately does not attempt to replicate CRABS's full database-curation feature set (multi-database sourcing, dereplication policy, taxonomic reconciliation); it does one narrow thing -- given a sequence and a primer pair, extract the amplicon region or report failure.

### unreferenced_candidates(match_df, rank_system = NULL, include_unreferenced_family = FALSE)

Add unreferenced taxon placeholder rows to a match object

Given a canonical match object (one row per 'observation_id' x reference accession), adds placeholder rows for taxon hypotheses absent from the reference database:

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. Canonical match object from TaxaMatch::standardize_match_data() or equivalent. Must contain observation_id, taxon_name, and taxon_name_rank. Taxonomy columns matching rank_system (e.g., family, genus, species) are used to derive H2/H3 taxon names. A score_original column is optional; when present it identifies the best anchor candidate. |
| rank_system | no | NULL | Character vector of rank names coarse to fine (e.g., c("family", "genus", "species")). When NULL (default), auto-detected from column names using TaxaTools::extended_ranks. At least two ranks are required. |
| include_unreferenced_family | no | FALSE | Logical (default FALSE). When TRUE, one "unreferenced_family" catch-all row is added per observation with all taxonomy columns set to NA. Use when running assign_scores() without TaxaExpect priors (e.g., the LLM shortcut pathway) to absorb posterior mass from taxa outside all represented families. Do not set to TRUE when using TaxaExpect priors -- the prior distribution already covers unrepresented families. |

**Value:** A data frame with the same columns as 'match_df', plus 'hypothesis_type' ('"specific_candidate"' for original rows; '"unreferenced_species"', '"unreferenced_genus"', or '"unreferenced_family"' for added rows). Added rows have 'score_original = NA' (and any other score columns set to 'NA').

#### Details

Both placeholder rows are anchored on the best-scoring H1 candidate for each observation (highest median score_original across accessions; first row if no scores are present). This is the same anchor convention used by evaluate_likelihoods().

The expanded data frame is passed to assign_scores() to obtain score_likelihood values.

### write_reference_fasta(reference_df, file, taxonomy_file = NULL, rank_system = NULL)

Write a Reference Data Frame to FASTA Format

Exports a 'reference_df' (from 'fetch_ncbi_reference_sequences()' or 'read_reference_fasta()') to a FASTA file compatible with BLAST, CRABS, Obitools, and other external tools. Optionally writes a companion taxonomy TSV in the same positional format accepted by 'read_reference_fasta()', making the export fully round-trippable.

| Param | Required | Default | Doc |
|---|---|---|---|
| reference_df | yes |  | Data frame with columns composite_id, sequence, and at least one taxonomy column from rank_system. Output of fetch_ncbi_reference_sequences(), read_reference_fasta(), or read_crabs_output(). |
| file | yes |  | Character. Output path for the FASTA file (e.g., "reference.fasta"). |
| taxonomy_file | no | NULL | Character or NULL. If not NULL, write a companion 2-column taxonomy TSV to this path. The file can be passed to read_reference_fasta() as taxonomy_file. |
| rank_system | no | NULL | Character vector of taxonomy columns to include, coarse to fine. Defaults to all taxonomy-like columns found in reference_df (everything except composite_id and sequence). |

**Value:** Invisibly returns 'reference_df'. Called for its side-effect of writing files.

#### Details

The FASTA header format is: >{composite_id} {rank1_value} {rank2_value} ... with taxonomy values joined by single spaces (missing ranks omitted). This is the most widely compatible header format for downstream tools.

The optional taxonomy TSV is a 2-column tab-delimited file (no header): column 1 = composite_id, column 2 = semicolon-separated taxonomy values in prefix-style format (e.g. f__Fundulidae;g__Fundulus;s__Fundulus heteroclitus). Prefix-style is used rather than positional format because positional parsing assumes a full 7-rank hierarchy from kingdom; any subset of ranks would map to the wrong positions. This file can be passed directly to read_reference_fasta() as taxonomy_file to reload the reference.

## Quick Start

``` r
library(TaxaLikely)

# 1. Fetch reference sequences from NCBI (National Center for
# Biotechnology Information, U.S. National Library of Medicine,
# National Institutes of Health, Bethesda, Maryland)
reference_df <- fetch_ncbi_reference_sequences(
  taxa = c("Fundulidae", "Gobiidae"),
  barcode_term = "12S"
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

