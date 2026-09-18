# CONTEXT: TaxaMatch

**Store and Standardize Biological Match Data**

Stores and standardizes raw match data produced by external tools that compare biological observations (eDNA sequences, images, acoustic recordings) against reference databases. Outputs a canonical match object (one row per sample x reference match, with standard column names) for input to TaxaLikely. Match data sources include DNA barcode programs (e.g. MiFish), image classifiers, and acoustic recognizers. Also screens reference accessions for taxonomic mislabeling via independent BLAST-based congruence checking before the reference set is used for likelihood model training. Score-to-likelihood conversion itself lives in TaxaLikely. Part of the TaxaID ecosystem.

Version 0.1.0 (built R 4.5.2; ; 2026-09-15 11:58:24 UTC; unix). 32 exported function(s).

## Functions

### add_lowest_consistent_rank(match_obj, rank_system = NULL, observation_id_col = "observation_id", na_as_inconsistent = FALSE, majority_threshold = NULL)

Add lowest consistent rank to a match object

For each observation, finds the finest taxonomic rank that has a single unambiguous value across all candidate rows. When four barnacle candidates share the same order but differ in family, genus, and species, the observation receives 'lowest_consistent_rank = "order"'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. Standardised match object containing at least 'observation_id_col' and the rank columns named in 'rank_system'. |
| rank_system | no | NULL | Character vector or 'NULL'. Rank columns to check, ordered coarse-to-fine (e.g. 'c("order","family","genus","species")'). Auto-detected when 'NULL' by matching column names against 'TaxaTools::extended_ranks'. |
| observation_id_col | no | "observation_id" | Character. Name of the observation identifier column (default '"observation_id"'). |
| na_as_inconsistent | no | FALSE | Logical. When 'TRUE', blank ('""') and 'NA' values count as a distinct category: a rank is flagged inconsistent when some candidates have no value and others do. Default 'FALSE': blanks and 'NA's are ignored and only non-blank values are compared. |
| majority_threshold | no | NULL | Numeric in (0, 1] or 'NULL' (default). When supplied, switches to majority mode: a rank is treated as consistent if the single most-common non-blank value accounts for at least this fraction of all non-blank candidate values. A value of '0.8' requires 4 of 5 candidates to agree. Values <= 0.5 are technically valid but semantically unusual (the "minority" would qualify as the majority). |

**Value:** 'match_obj' with one new column in strict mode, or four new columns in majority mode: 'lowest_consistent_rank' Character. The finest rank for which the consistency criterion is satisfied. 'NA' when no rank passes. 'rank_majority_value' (_majority mode only_) Character. The majority value at 'lowest_consistent_rank' for the observation. 'NA' when 'lowest_consistent_rank' is 'NA'. 'rank_majority_fra

### assign_spatial_group(sites, observation_ids, spatial_group_id, id_col = "observation_id")

Manually Assign a Spatial Group to a Set of Observations

Sets 'spatial_group_id' directly for a named set of observations - for a study where the grouping is already known from metadata, or to hand-correct a few observations after 'group_observations_by_bbox''s interactive step - without drawing boxes. Guards against the one way this could silently corrupt an existing group: if 'spatial_group_id' is already in use by an observation *not* named in this call, that would silently expand an unrelated group's membership the next time anyone counts by 'spatial_group_id'. This function stops instead, so the caller can either include that observation explic

| Param | Required | Default | Doc |
|---|---|---|---|
| sites | yes |  | Data frame with (at least) 'id_col', 'spatial_group_id', and 'spatial_group_N' columns - typically the output of 'build_site_table' or 'group_observations_by_bbox'. |
| observation_ids | yes |  | Character vector of 'id_col' values to assign to 'spatial_group_id'. Must all already exist in 'sites'. |
| spatial_group_id | yes |  | Character. Single, non-empty group id to assign. Can be a new id or an existing one (to add members to an already-formed group); see Details for the collision guard. id_col: Character. Observation ID column name. Default '"observation_id"'. |
| id_col | no | "observation_id" |  |

**Value:** 'sites' with 'spatial_group_id' set to 'spatial_group_id' for the named observations, 'spatial_group_N' recomputed for that group so it stays in sync, and (when present) 'is_default_group' set to 'FALSE' for the named observations - they are no longer eligible to be captured by a future 'group_observations_by_bbox' call. All other rows are unaffected.

### blast_sequences(seq_df, method = "remote", database = "nt", program = "blastn", megablast = FALSE, score_range = 8, max_hits = 20L, max_hits_per_taxon = NULL, min_score = 70, min_query_coverage = 80, barcode_term = NULL, min_subject_length = NULL, max_subject_length = NULL, max_target_seqs = 100L, batch_size = 20L, max_batch_bp = 100000L, email = Sys.getenv("NCBI_EMAIL", unset = ""), ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), resolve_taxonomy = TRUE, resolve_location = FALSE, poll_max_wait = 1800, max_consecutive_batch_failures = 3L, verbose = TRUE)

BLAST Sequences Against NCBI or a Local Database

Searches query sequences against NCBI nucleotide (remote) or a local BLAST database, then filters hits using a score window approach: retain all hits within 'score_range' percent identity of each query's top hit, up to 'max_hits' per query.

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_df | yes |  | Data frame with at least 'asv_id' and 'sequence' columns (e.g., output of 'read_sequence_table' or 'filter_sequences'). method: Character: '"remote"' (default) to use the NCBI BLAST URL API, or '"local"' to use a local BLAST+ database via the 'rBLAST' package. |
| method | no | "remote" |  |
| database | no | "nt" | For remote: NCBI database name (default '"nt"'). For local: path to a local BLAST database. program: BLAST program. Default '"blastn"'. |
| program | no | "blastn" |  |
| megablast | no | FALSE | Logical. Default 'FALSE'. Both the NCBI BLAST URL API (remote) and the standalone 'blastn' binary (local, via 'rBLAST') default an unqualified 'program = "blastn"' search to MEGABLAST mode when this isn't set explicitly - a fast, greedy algorithm tuned to find _a_ highly-similar hit quickly, not to exhaustively return every equally-good one. Confirmed on real data: a query with five reference sequences from one species and five from a second, genuinely tied at 100\ one species and none from the other under the implicit (megablast) default - silently dropping a real, exactly-tied congener before 'score_range' filtering ever had a chance to keep it. Set 'TRUE' to restore the old implicit (unspecified/megablast) behavior for speed on very large batches; 'FALSE' (classic blastn) is slower but the only mode confirmed to return every near-identical reference, which is what 'score_range''s own tie-detection depends on. |
| score_range | no | 8 | Numeric. Keep all hits within this many percent identity points of each query's top hit (default '8', widened from an earlier default of '2' - see "Score window validation" below). For example, if the top hit is 99% identity, all hits at 91% or above are retained. Wider ranges capture more taxonomic alternatives; narrower ranges (e.g., 2) focus on the closest matches only but risk silently dropping the true species when a congener happens to score higher (see Details). |
| max_hits | no | 20L | Integer. Safety cap: maximum hits to retain per query after score window filtering (default '20L'). Increase for queries expected to match many closely related species. |
| max_hits_per_taxon | no | NULL | Integer or 'NULL' (default). When set, caps the number of hits retained per taxon _before_ 'max_hits' is applied. Without this, one heavily-resequenced species - e.g. a genus with many independently deposited mitogenomes of the same well-studied species - can consume the entire 'max_hits' budget with redundant near-duplicate hits, silently crowding out a real, different congener that would otherwise have survived 'score_range' filtering. Each taxon's own best-scoring hit is always kept, so this never changes which taxon has the top score. Set to e.g. '3L' to keep at most 3 representative hits per species. *Requires 'resolve_taxonomy = TRUE' to have any effect on remote BLAST results.* Remote BLAST's XML output never populates a real per-hit taxid ('staxids' is always 'NA' there), so grouping would otherwise be a silent no-op - every hit would land in its own singleton group. When both are set, taxonomy is resolved once, early (on the min_score/coverage/length survivors, before this cap and 'max_hits' run) specifically so grouping can use the real resolved species/genus name; the normal end-of-pipeline taxonomy resolution step is skipped since it's already done. This does mean more NCBI taxonomy lookups than the 'resolve_taxonomy = TRUE' default alone (resolved on the larger pre-'max_hits' set, not the smaller final one) - a real cost, only incurred when 'max_hits_per_taxon' is actually requested. With 'resolve_taxonomy = FALSE', this falls back to grouping by 'staxids' (a no-op for remote results, same as before this parameter existed) - local BLAST via 'rBLAST' does supply real 'staxids' directly from its own database's taxonomy mapping, so this fallback is only inert for the remote path. |
| min_score | no | 70 | Numeric. Discard hits below this percent identity (default '70'). The 70% threshold is a conventional cross-genus floor for DNA barcoding; most true species-level matches exceed 95%. |
| min_query_coverage | no | 80 | Numeric. Discard hits where less than this percentage of the query sequence aligned (default '80'). Standard BLAST quality filter; ensures hits span most of the barcode region. |
| barcode_term | no | NULL | Character. Barcode marker name for auto-detecting the expected amplicon length bounds (e.g., '"12S"', '"COI"'). Default 'NULL'. |
| min_subject_length | no | NULL | Integer. Minimum length, in bp, of the _aligned region_ against the reference (not the reference accession's own total sequence length - see Details). Overrides 'barcode_term'. Default 'NULL'. |
| max_subject_length | no | NULL | Integer. Maximum length, in bp, of the aligned region against the reference. Overrides 'barcode_term'. Default 'NULL'. |
| max_target_seqs | no | 100L | Integer. Number of hits to request from BLAST before client-side filtering (default '100L'). Should be generous (larger than 'max_hits') since NCBI's default is 500. Set higher (e.g., 500) for comprehensive searches; lower for speed. |
| batch_size | no | 20L | Integer. For remote BLAST, number of sequences per submission (default '20L'). Larger batches reduce API overhead but risk timeout on NCBI's server. NCBI handles multi-FASTA queries. |
| max_batch_bp | no | 100000L | Numeric. Remote BLAST only. Default '100000L'. Cumulative-length (bp) cap per submission batch, applied ALONGSIDE 'batch_size' - a batch closes when EITHER the count or the bp limit is reached, whichever comes first. Added 2026-09-01: a long query (e.g. one of several full mitogenomes sharing a batch with mostly short amplicons) consumes vastly more server CPU than its count-based "1 of 'batch_size'" share suggests - one expensive query can doom an otherwise-cheap batch to a CPU-budget rejection ('.blast_server_rejected()'), and losing that whole batch to 'max_consecutive_batch_failures''s circuit breaker costs every query it was sharing with, not just the expensive one. A single query at or above half of 'max_batch_bp' rides ALONE in its own batch (closing whatever batch was already accumulating first, if any) - isolating it this way guarantees a doomed batch only ever costs that ONE query's own progress. 'Inf' disables the bp cap entirely, fully restoring the old count-only 'batch_size' behavior. See '.split_batches_by_length()' for the implementation. Most calls at the default 'batch_size'/typical amplicon lengths never approach '100000L' bp per batch, so this is a no-op for ordinary data - it only ever triggers for real long-sequence batches. email: Character. Email address sent to NCBI (required by their usage policy for remote BLAST). Defaults to the 'NCBI_EMAIL' environment variable (unset by default); a 'warning()' is issued for remote BLAST when neither is available. |
| email | no | Sys.getenv("NCBI_EMAIL", unset = "") |  |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | Character. Optional NCBI API key for higher rate limits. Defaults to the 'NCBI_API_KEY' environment variable (unset by default). |
| resolve_taxonomy | no | TRUE | Logical. If 'TRUE' (default), resolve NCBI taxonomy IDs to full lineage (kingdom through species) and append taxonomy columns to the output. |
| resolve_location | no | FALSE | Logical. Default 'FALSE'. If 'TRUE', fetch each unique hit accession's full GenBank record (a real, separate NCBI round trip - not free) and append 'lat'/'lon'/ 'country' columns parsed from the record's 'source' feature 'lat_lon'/'country' qualifiers. 'NA' where the record has no collection-location metadata. Independent of 'resolve_taxonomy' - taxonomy comes from the NCBI taxonomy database, location from the full nucleotide record; neither fetch gives you the other. |
| poll_max_wait | no | 1800 | Numeric. Remote BLAST only. Seconds to keep polling NCBI for a submitted batch's results before giving up on it (default '1800', i.e. 30 minutes). Raised from an earlier hardcoded '600' (2026-08-09) after a real, large (1,183-accession) remote- BLAST run observed sustained per-batch queue waits exceeding 600s. A batch that still exceeds this window (even after the existing halved-batch-size retry), OR that NCBI reports 'Status=READY' for but has actually aborted server-side for exceeding a CPU-time fair-use budget (see '.blast_server_rejected()''s own documentation for the real captured case that found this - a real, distinct failure mode from a poll timeout, since NCBI returns a genuine, successfully- retrieved XML document, just one recording a rejection instead of real search results), is recorded in 'attr(result, "failed_query_ids")' - the affected 'asv_id's, so a caller can tell "search never completed or was rejected" apart from "search completed and found nothing," which 'evaluate_reference_accessions()' uses to avoid caching a failed batch's accessions as if they were a real verdict. Neither failure mode is fixable by raising this parameter alone - a CPU-budget rejection means NCBI is actively throttling this IP address's remote-BLAST usage; the real remedy is fewer/smaller/less frequent real calls (or 'method = "local"' for a large batch job), not a longer wait. |
| max_consecutive_batch_failures | no | 3L | Integer. Remote BLAST only. Default '3L'. A circuit breaker, distinct from 'poll_max_wait' - that parameter bounds how long ONE batch is allowed to take; this bounds how many CONSECUTIVE batches are allowed to fail before concluding the problem is systemic (sustained NCBI rate-limiting or CPU-budget throttling), not one unlucky batch, and stopping rather than continuing to submit batches that are likely doomed too. Without this, a sustained throttling episode means every remaining batch still pays its own full 'poll_max_wait' before giving up - for a large run (e.g. 60 batches at the default 'batch_size'), that is many hours of guaranteed-doomed work before the function ever returns. A '.blast_server_rejected()' rejection counts double toward this threshold (a real, unambiguous throttle signal from NCBI itself); a plain poll timeout or submission failure counts once (could just be one slow/large batch). The counter resets to 0 on any batch that completes normally (including a real zero-hit result). When tripped: no further batches are submitted, every not-yet-attempted batch's queries are added to 'failed_query_ids' (see below) alongside whatever had already failed, and the halved-batch-size retry pass is skipped entirely (retrying under a confirmed-systemic throttle wastes real NCBI time on batches already judged doomed). Set to 'Inf' to disable and restore the old unconditional-retry-every-batch behavior. verbose: Logical. Print progress messages. Default 'TRUE'. |
| verbose | no | TRUE |  |

**Value:** A data frame with one row per query x hit, containing: observation_id Query identifier (from 'asv_id') accession Subject accession score Percent identity (0-100 scale), computed as 'round(100 * identity / align_len, 2)' from HSP fields (the standard NCBI definition). This is _alignment_ identity over the aligned region, not sequence identity over the full query length. For multi-HSP alignments onl

### build_site_table(match_df, site_df = NULL, id_col = "observation_id")

Build a Unified Long-Format Site Table

Produces one standardized site table - 'observation_id', 'lat', 'lon', 'observed_on' - regardless of which data-type pathway produced 'match_df'. This closes a contract gap across the three pathways: 'score_image_inat''s output already carries per-observation 'lat'/'lng'/'observed_on', but 'standardize_match_data' (DNA/BLAST) and 'read_birdnet_output' (acoustic) carry neither - for those, site information must be supplied separately via 'site_df'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | A match-object data frame from any TaxaMatch ingest function ('score_image_inat', 'read_birdnet_output', 'standardize_match_data', ...). site_df: Data frame with (at minimum) 'id_col', 'lat', and 'lon' columns, required when 'match_df' has no embedded 'lat'/'lng'. Optional 'observed_on' column. *May have more than one row per 'id_col' value* - this is the correct shape for a sequence ASV genuinely detected at several real sample sites (the same 'observation_id' legitimately gets one row per site); do not pre-collapse to one row per observation before calling. Ignored (with a warning) when 'match_df' already carries embedded site info. id_col: Character. Observation ID column name, present in both 'match_df' and 'site_df'. Default '"observation_id"'. |
| site_df | no | NULL |  |
| id_col | no | "observation_id" |  |

**Value:** A tibble in long format: one row per '(observation_id, site)' pair actually present in 'match_df', with columns 'id_col', 'lat', 'lon', 'observed_on' ('NA' where unknown), 'spatial_group_id', 'spatial_group_N', and 'is_default_group'. 'spatial_group_id' defaults to '"spatial_group_<n>"', grouping rows that share an *exact* '(lat, lon)' pair (see Details), and 'spatial_group_N' to the count of rows

### check_marker_mismatch(accessions, expected_marker, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), verbose = TRUE)

Cross-Check a Reference Accession's Own Annotated Gene/Product Against an Expected Marker

Before investigating a flagged accession as a possible SPECIES mislabel (see 'investigate_flagged_accession()'), this does a single cheap GBSeq XML fetch and checks the record's own /gene or /product feature-table qualifier against the marker an evaluation was scoped to (e.g. does a "12S"-scoped audit's flagged record actually say /product="16S ribosomal RNA"?). No BLAST, no alignment - much cheaper than 'investigate_flagged_accession()''s deep dive, and meant to route a flagged accession to a completely different, simpler resolution path (correct the marker label, or exclude the accession fro

| Param | Required | Default | Doc |
|---|---|---|---|
| accessions | yes |  | Character vector of accessions to check. |
| expected_marker | yes |  | Character scalar (e.g. '"12S"', '"16S"', '"COI"') - the marker/barcode the evaluation this accession was flagged under was scoped to. Matched case-insensitively against a small internal lookup of common marker-name synonyms as they actually appear in real GenBank /gene//product qualifiers (e.g. '"12S"' also matches '"s-rRNA"'/'"small subunit ribosomal RNA"'); an unlisted marker falls back to a literal, case-insensitive substring match on 'expected_marker' itself. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | As in 'evaluate_reference_accessions()'. |
| verbose | no | TRUE | As in 'evaluate_reference_accessions()'. |

**Value:** A data frame, one row per unique input accession: 'accession' As supplied. 'expected_marker' As supplied. 'annotated_genes' Semicolon-joined, deduplicated /gene qualifier values found anywhere in the record's feature table. 'NA' if none were found (may still have /product annotation). 'annotated_products' Same, for /product. 'marker_match' 'TRUE' if ANY annotated /gene or /product text matches 'ex

### convert_taxonomy_backbone(match_df, target_backbone_id, source_backbone_id = NULL, rank_system = c("order", "family", "genus", "species"), taxon_col = "taxon_name", update_taxon_name = TRUE, original_col = "taxon_name_original", backbone_col = "taxonomy_backbone", collision_col = "taxonomy_collision", verify_fn = TaxaTools::verify_taxon_names, verbose = TRUE)

Convert Match Object Taxonomy to a Target Backbone

Looks up each unique taxon name in 'match_df[[taxon_col]]' against a target taxonomic backbone (e.g. GBIF, NCBI), then replaces rank columns with the target backbone's hierarchy wherever the target provides a non-NA value (_per-column fallback_: ranks the target omits are left unchanged).

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | A data frame containing a taxon name column and rank columns. |
| target_backbone_id | yes |  | Integer. The target backbone identifier. Standard IDs: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS, 11 = GBIF. See <https://verifier.globalnames.org/> for the full list. |
| source_backbone_id | no | NULL | Integer or 'NULL'. The backbone that produced 'match_df''s current hierarchy. Used only to label the 'taxonomy_collision' column for rows not found in the target backbone. When 'NULL' (default), not-found rows are labelled '"original"'. |
| rank_system | no | c("order", "family", "genus", "species") | Character vector of rank column names to compare and potentially update, listed broadest to finest (e.g. 'c("order", "family", "genus", "species")'). Columns absent from 'match_df' are silently skipped. |
| taxon_col | no | "taxon_name" | Character. Name of the column containing the taxon name used as the lookup key (default '"taxon_name"'). |
| update_taxon_name | no | TRUE | Logical. When 'TRUE' (default), 'match_df[[taxon_col]]' is updated to the target backbone's accepted name (authority strings stripped via 'TaxaTools::clean_taxon_names()'). The original value is preserved in 'match_df[[original_col]]'. |
| original_col | no | "taxon_name_original" | Character. Name of the column to receive the original taxon name when 'update_taxon_name = TRUE' (default '"taxon_name_original"'). Created if absent; unchanged if already present. |
| backbone_col | no | "taxonomy_backbone" | Character. Name of the column recording which backbone each row's hierarchy came from (default '"taxonomy_backbone"'). Created if absent. |
| collision_col | no | "taxonomy_collision" | Character. Name of the column recording the per-row conversion outcome (default '"taxonomy_collision"'). Created if absent. |
| verify_fn | no | TaxaTools::verify_taxon_names | Function. The name verification function to call. Must accept a character vector as its first argument and a 'backbone_id' argument; must return a data frame with columns 'user_supplied_name', 'matched_name', 'classification_path', 'classification_ranks', and 'verified' (logical: 'TRUE' when the name resolved in the target backbone, 'FALSE'/'NA' otherwise). An optional 'matched_rank' column (the rank 'matched_name' actually resolved at) enables the rank correction described below; a 'verify_fn' without it is still fully supported, just without that correction. Default: TaxaTools::verify_taxon_names. Override for offline testing via dependency injection. The call is wrapped in 'tryCatch()'; a failure (e.g. network unavailable, API rate-limited) raises a clear error naming the likely cause rather than propagating whatever uninformative error the API layer produced. verbose: Logical. Print the backbone column mapping summary message at the end. Default 'TRUE'. 'warning()'s for inconsistent taxonomy are always issued regardless of this setting. |
| verbose | no | TRUE |  |

**Value:** 'match_df' with rank columns potentially updated, plus 'backbone_col', 'collision_col', and (when 'update_taxon_name = TRUE') 'original_col' columns added - 'backbone_col'/'collision_col' are created if absent and left unchanged (not overwritten) if already present, which matters for iterative/multi-pass pipeline use. The attribute 'backbone_cols' is set: a named list mapping '"backbone_N_cols"' t

### corroborate_references_locally(seq_matrix, reference_meta, min_overlap = 0.8, min_pident = 0.99, submission_window = 5L)

Corroborate Reference Labels From the Local Reference Set, Without BLAST

For each reference accession, asks whether an INDEPENDENT conspecific in the caller's own reference set (the one 'TaxaLikely::build_sequence_matrix()' was built from) matches it at high identity over most of the amplicon. A reference so corroborated does not need the BLAST screen ('evaluate_reference_accessions()') to confirm its label - and if the BLAST screen nevertheless says '"remove"', the local evidence vetoes that ('score_reference_labels()'). Zero NCBI cost.

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_matrix | yes |  | Data frame. 'TaxaLikely::build_sequence_matrix()' output: 'id_x', 'id_y', 'p_match' (0-1), 'coverage' (0-1), 'species.x', 'species.y'. Either a full pairwise table or one triangle - pairs are symmetrised internally. |
| reference_meta | yes |  | Data frame. One row per reference: 'composite_id' (or 'accession') and, optionally, 'create_date' (a 'Date', or a string in '"%Y/%m/%d"' or '"%Y-%m-%d"' form) and 'species'. The 'TaxaLikely::fetch_ncbi_reference_sequences()' reference_df is exactly this. Without 'create_date', independence falls back to the accession-number heuristic alone. |
| min_overlap | no | 0.8 | Numeric in (0, 1] (default '0.8'). Minimum 'coverage' for a pair to count at all. |
| min_pident | no | 0.99 | Numeric in (0, 1] (default '0.99'). Minimum identity of the best independent conspecific for 'local_tier = "corroborated"'. |
| submission_window | no | 5L | Integer (default '5L'). As in 'evaluate_reference_accessions()'; pass the same value used there. |

**Value:** A data frame, one row per accession (version suffix stripped) in the union of 'reference_meta' and 'seq_matrix': 'accession' Version-stripped id. 'species' From 'reference_meta$species' when present, else the accession's 'species.x' in 'seq_matrix'. 'n_conspecific' Distinct conspecific partners at 'coverage >= min_overlap', any batch. 'n_independent_conspecific' Of those, from a different submissi

### evaluate_reference_accessions(accessions, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), insufficient_evidence_ttl_days = 180, incongruent_ttl_days = 30, top_n = 5L, min_congruent_rank = "family", hierarchy_incongruent_threshold = 0.5, min_independent_partners = 3L, submission_window = 5L, method = c("remote", "local"), database = "nt", score_range = 8, min_score = 70, max_hits = 20L, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), poll_max_wait = 1800, barcode_term = NULL, query_span = c("amplicon", "primer_inclusive"), chunk_size = 200L, max_consecutive_batch_failures = 3L, max_query_len = NULL, max_batch_bp = 100000L, prioritize_uncached = TRUE, retry_insufficient = TRUE, local_corroboration = NULL, skip_locally_corroborated = TRUE, verbose = TRUE)

Evaluate Reference-Accession Quality via Unrestricted BLAST Comparison

For each accession, BLASTs its own sequence against a broad, *unrestricted* database (not scope-limited to any caller-chosen taxon list), applies the same-submission-batch independence filter, and computes a Jeffreys-smoothed taxonomic-hierarchy congruence verdict - the same congruence math 'TaxaLikely::audit_reference_database()'/'classify_reference_accessions()' used to compute from a narrow, taxon-list-scoped DECIPHER alignment, now fed from real, broad BLAST hits instead.

| Param | Required | Default | Doc |
|---|---|---|---|
| accessions | yes |  | Character vector of NCBI accessions to evaluate. Deduplicated internally. |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | Character or 'NULL'. Default 'tools::R_user_dir("TaxaMatch", "cache")'. Set 'NULL' to disable caching entirely (every call re-evaluates every accession). |
| insufficient_evidence_ttl_days | no | 180 | Numeric (default '180'). See Caching above. |
| incongruent_ttl_days | no | 30 | Numeric (default '30'). Days after which an '"incongruent"' cached verdict is re-evaluated. 'Inf' restores the pre-2026-09-02 behaviour (cached indefinitely). Much shorter than 'insufficient_evidence_ttl_days' on purpose, for two compounding reasons: '"incongruent"' is the only verdict that causes a reference to be REMOVED, and the thing that goes stale underneath it - NCBI's 'nt' snapshot - is rebuilt on the order of days to weeks, not months. It is also ~1% of a real accession population (12 of 995 on the PtConception screen), so this is simultaneously the most valuable and the cheapest recheck available. See @section Why "incongruent" gained a TTL. top_n: Integer (default '5L'). Max independent BLAST hits ranked per accession for the congruence verdict. |
| top_n | no | 5L |  |
| min_congruent_rank | no | "family" | Character (default '"family"'). Passed to the shared congruence math - see 'TaxaLikely::audit_reference_database()''s own roxygen for why '"family"', not a coarser rank, is this ecosystem's default. |
| hierarchy_incongruent_threshold | no | 0.5 | Numeric (default '0.5'). An accession's smoothed 'frac_independent_below_min_congruent_rank' at or above this value reads '"incongruent"'. |
| min_independent_partners | no | 3L | Integer (default '3L'). Fewer independent top matches than this reads '"insufficient_independent_evidence"' regardless of the fraction - mirrors 'TaxaLikely::repair_thin_evidence()''s identical floor. |
| submission_window | no | 5L | Integer (default '5L'). Days (or accession-number proximity) within which two accessions are treated as the same submission batch, and therefore non-independent evidence of each other. |
| method | no | c("remote", "local") | Passed through to 'blast_sequences()' - see that function's own documentation. |
| database | no | "nt" | Passed through to 'blast_sequences()' - see that function's own documentation. |
| score_range | no | 8 | Passed through to 'blast_sequences()' - see that function's own documentation. |
| min_score | no | 70 | Passed through to 'blast_sequences()' - see that function's own documentation. |
| max_hits | no | 20L | Passed through to 'blast_sequences()' - see that function's own documentation. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | Character or 'NULL'. Optional NCBI API key for higher rate limits (also forwarded to 'blast_sequences()'). |
| poll_max_wait | no | 1800 | Numeric (default '1800', i.e. 30 minutes). Forwarded to 'blast_sequences(poll_max_wait =)' - how long to keep polling NCBI for one BLAST batch's results before giving up on it. An accession whose batch times out (even after 'blast_sequences()''s own automatic halved-batch-size retry) is treated the same as one NCBI has no record for at all - excluded from this call's cache write and reported via $unresolved-style warning, NOT scored as '"insufficient_independent_evidence"' - a real, previously-possible silent-miscache risk found 2026-08-09 on a real, large (1,183- accession), multi-hour remote-BLAST run: sustained NCBI queue congestion caused most batches after the first to time out at the old hardcoded 600s ceiling, and every one of those accessions would otherwise have been cached as a false '"insufficient_independent_ evidence"' verdict for up to 'insufficient_evidence_ttl_days' (180 days by default) - masking the real infrastructure failure as if it were a genuine evidentiary finding. |
| barcode_term | no | NULL | Character or 'NULL' (default). When supplied, any query sequence exceeding the marker's expected length (via 'TaxaTools::resolve_barcode_lengths(barcode_term)') is trimmed to its amplicon region (via 'TaxaTools::resolve_barcode_primers(barcode_term)' • the same primer-matching algorithm as 'TaxaLikely::trim_to_amplicon()', duplicated here - see '.extract_amplicon_one_tm()''s own documentation) before being BLASTed, instead of submitting the full sequence. BLASTing a full-length over-length reference (e.g. a complete mitogenome, ~16.5kb) against a broad database is dramatically more CPU-expensive than BLASTing its short barcode region, and was found 2026-08-09 to be the real cause of a live NCBI server-side CPU-budget rejection on a real, large run whose queries were often full mitogenomes (see 'poll_max_wait''s own documentation for the real captured case) - the accession's own species-identity signal lives in the short barcode region regardless, so trimming answers the identical question at a fraction of the cost. A sequence whose primer sites can't be found is next tried against the record's own annotated feature table (2026-09-01 - see @section Long-sequence robustness below), then, if still over-length, subject to the 'max_query_len' hard cap - never silently dropped or errored either way; at worst it is deferred as '"not_evaluated_oversized"', an explicit, labeled, TTL-retryable non-result. 'NULL' (default) submits every sequence at full length, unchanged from prior behavior. |
| query_span | no | c("amplicon", "primer_inclusive") | Character, '"amplicon"' (default) or '"primer_inclusive"'. Which span of a 'barcode_term'-trimmed query is submitted to BLAST: the primer-STRIPPED amplicon (the region between the two primer sites, ~169 bp for MiFish-U) or the primer-INCLUSIVE span (~217 bp), the only behaviour before 2026-09-03. See @section Why the query is the primer-stripped amplicon. Verdict-affecting, so it is part of 'params_key'. Ignored when 'barcode_term' is 'NULL' (nothing is trimmed), and moot for a marker with no registered primer pair in 'TaxaTools::barcode_primer_defaults' (e.g. '"18S"', '"ITS"'): such queries are submitted AS DEPOSITED with a one-line message, never trimmed and never an error (2026-09-12; previously the whole screen died on its first chunk for 18S). Over-length records still go to the feature-table fallback. |
| chunk_size | no | 200L | Integer (default '200L'). Accessions needing real evaluation are processed this many at a time, with the persistent cache written after EACH chunk - see @section Chunked evaluation and NCBI rate-limiting resilience below. 'Inf' restores the pre-2026-08-14 single-shot behavior (one chunk covering every accession, cache written only once at the very end). |
| max_consecutive_batch_failures | no | 3L | Numeric (default '3L'). Forwarded to 'blast_sequences()' - see that function's own documentation for the full circuit-breaker mechanism (a '.blast_server_rejected()' rejection counts double toward this threshold; a plain poll timeout counts once). 'Inf' disables it. |
| max_query_len | no | NULL | Numeric or 'NULL' (default). The hard submission cap - after BOTH 'barcode_term' rescue strategies (primer trimming, then the feature-table-guided extraction fallback) have been tried, any query still longer than this is NOT submitted to BLAST at all. 'NULL' resolves a default: 10x the marker's own 'amplicon_range' upper bound (via 'TaxaTools::resolve_barcode_primers(barcode_term)') when 'barcode_term' is supplied - generous enough to never reject a real amplicon-length sequence, but small enough to exclude a full mitogenome or larger record - or a flat '5000' when it is not (no marker-specific bound to derive one from). 'Inf' disables the cap entirely, restoring the pre-2026-09-01 behavior (an unrescuable over-length query is always BLASTed at full length). See @section Long-sequence robustness below for the full mechanism and the new '"not_evaluated_oversized"' verdict this produces. |
| max_batch_bp | no | 100000L | Numeric (default '100000L'). Forwarded to 'blast_sequences()' - see that function's own documentation for the length-aware BLAST batching this adds alongside the existing count-based batching. 'Inf' disables it. |
| prioritize_uncached | no | TRUE | Logical (default 'TRUE'). Orders 'needs_eval' so accessions with NO existing cached verdict under the current call's parameters are evaluated before expired '"insufficient_independent_evidence"'/'"not_evaluated_oversized"' rows being retried past their TTL - a budget-limited call (one that trips 'blast_sequences()''s own circuit breaker partway through) buys real NEW coverage first, rather than re-spending BLAST budget re-checking accessions that already have SOME cached answer. A pure ordering change within one call - never changes which accessions end up evaluated, only in what order - so, unlike every other new parameter here, this one changes existing default behavior deliberately: it is strictly better (or a no-op), never worse. |
| retry_insufficient | no | TRUE | Logical (default 'TRUE'). 'FALSE' skips retrying EXPIRED '"insufficient_independent_evidence"'/ '"not_evaluated_oversized"' cached rows entirely for this call - they are served from cache as-is (their TTL notwithstanding) instead of being re-submitted to NCBI. Addresses a real documented complaint: by default, a call the caller expects to be purely cache-served (every accession already evaluated at least once) can still spend real BLAST budget re-checking every TTL-expired row, grinding against the same CPU-budget throttle this whole feature exists to survive. Set 'FALSE' on a call where zero new NCBI cost is required this time. |
| local_corroboration | no | NULL | Data frame or 'NULL' (default). Output of 'corroborate_references_locally()' for the caller's own reference set. When supplied (and 'skip_locally_corroborated = TRUE'), any accession whose 'local_tier' is '"corroborated"' and that has no fresh cached verdict is NOT BLASTed: it is written to the cache as 'hierarchy_flag = "locally_corroborated"' with 'n_independent_top_matches = n_independent_conspecific', 'best_agreeing_pident = 100 * best_independent_pident', 'congruent_evidence_exists_anywhere = TRUE', 'finest_common_rank = "species"', and every other diagnostic 'NA'. See @section Local corroboration. |
| skip_locally_corroborated | no | TRUE | Logical (default 'TRUE'). 'FALSE' sends locally-corroborated accessions to BLAST like any other, and also re-evaluates any row previously cached as '"locally_corroborated"' (that flag records a decision not to evaluate, not an evaluation). Not part of 'params_key'. verbose: Logical (default 'TRUE'). Print progress messages. |
| verbose | no | TRUE |  |

**Value:** A data frame, one row per unique input accession: 'accession' Exactly as supplied by the caller. 'listed_taxon' The accession's own labeled organism (from its real GenBank record). 'n_independent_top_matches' Independent BLAST hits actually used for the verdict (<= top_n). Also excludes any hit whose OWN listed species isn't itself resolved to species level - see @section Species-resolved comparis

### filter_redundant_hypotheses(match_df, rank_system = c("kingdom", "phylum", "class", "order", "family", "genus", "species"))

Filter Redundant Higher-Rank Hypotheses

Removes coarser-rank rows that are superseded by finer-rank rows within the same lineage and 'observation_id'. Redundancy is *lineage-local*: a genus-level row for _Gobius_ is dropped only if a _Gobius_ species row also exists for the same 'observation_id'. A genus row for a different lineage (e.g., _Acanthogobius_) is retained even when _Gobius_ species rows are present.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | A data frame with at minimum the columns 'observation_id', 'taxon_name_rank', and one column for each rank named in 'rank_system'. Rows whose 'taxon_name_rank' is not found in 'rank_system' are retained unchanged and a warning is emitted listing the unrecognised values. Rows with 'NA' 'taxon_name_rank' are also silently retained (no warning) - they cannot be compared against 'rank_system' at all. Two species-level rows for different species sharing the same genus/family (e.g. _Gobius paganellus_ and _Gobius bucchichi_) are both retained and neither's genus row is dropped - this function only removes strictly redundant ancestor rows, not competing same-rank candidates (disambiguating those is TaxaLikely's job). |
| rank_system | no | c("kingdom", "phylum", "class", "order", "family", "genus", "species") | Character vector of taxonomic rank names in *coarsest-to-finest* order. Defaults to 'c("kingdom","phylum","class","order","family","genus","species")'. Each name must match both an element of 'taxon_name_rank' *and* a column name in 'match_df' (case-sensitive after 'standardize_match_data()' has lowercased everything) - if 'match_df' has not been through 'standardize_match_data()', rank column names may not match this default and no rows will be removed (a 'warning()' is issued when none of 'rank_system' matches a 'match_df' column at all). |

**Value:** A data frame with the same columns as 'match_df' but with redundant higher-rank rows removed. Row order and all other attributes are preserved.

### filter_sequences(seq_df, barcode_term = NULL, min_length = NULL, max_length = NULL, min_abundance = 2L)

Filter Sequences by Length and Abundance

Removes sequences that fall outside acceptable length bounds or below a minimum abundance threshold. Length bounds can be set automatically from a barcode marker name or specified manually.

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_df | yes |  | Data frame from 'read_sequence_table', or any data frame with 'sequence' (or 'length') and 'abundance' columns. |
| barcode_term | no | NULL | Character string identifying the barcode marker (e.g., '"12S"', '"COI"', '"MiFish"'). Used to auto-detect length bounds. Ignored if both 'min_length' and 'max_length' are specified. Default 'NULL'. |
| min_length | no | NULL | Minimum sequence length in base pairs. Overrides 'barcode_term' default. Default 'NULL'. |
| max_length | no | NULL | Maximum sequence length in base pairs. Overrides 'barcode_term' default. Default 'NULL'. |
| min_abundance | no | 2L | Minimum total read count to retain a sequence. Sequences with fewer reads are removed. Default '2' (removes singletons). |

**Value:** A filtered data frame (same structure as input). A message reports how many sequences were removed and why. An 'attr(out, "report_params")' list ('min_length', 'max_length', 'min_abundance', 'n_retained') is also attached, mirroring 'blast_sequences()''s own 'report_params' attribute, so downstream reporting functions can incorporate the filtering parameters into automated methods text.

### flag_incongruent_references(match_df, evaluation)

Annotate a Match Object with Reference-Accession Quality, Without Removing Anything

The RECOMMENDED default consumer of 'evaluate_reference_accessions()' - left-joins its evaluation columns onto 'match_df' by accession (version-suffix-stripped, same convention as 'remove_incongruent_references()') so 'hierarchy_flag' and the identity/ coverage diagnostics travel with the match object for review, without ever discarding a candidate taxon.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. A standardized match object (from 'standardize_match_data()') containing an 'accession' column. |
| evaluation | yes |  | Data frame. Output of 'evaluate_reference_accessions()'. |

**Value:** 'match_df' with 'hierarchy_flag', 'finest_common_rank', 'frac_independent_below_min_congruent_rank', 'n_independent_top_matches', 'n_top_matches_available', 'best_hit_pident', 'best_agreeing_pident', 'best_disagreeing_pident', 'congruent_evidence_exists_anywhere', and 'congruent_evidence_best_pident' joined on, plus 'label_confidence', 'label_identity_margin', 'reference_action' and 'listed_taxon_

### group_observations_by_bbox(sites, id_col = "observation_id", lat_col = "lat", lon_col = "lon", tile = "Esri.OceanBasemap")

Group Observations by User-Drawn Bounding Boxes

Plots all observations' site coordinates and lets the user draw one or more bounding-box polygons (via repeated calls to 'define_search_polygon') to define spatial groups. Observations whose coordinates fall within a drawn box share a 'spatial_group_id' and can use one pooled, community-level occurrence/reference fetch (the existing clustered pipeline design). Observations that never fall inside any drawn box - including every observation, if the user draws no box at all - are *not dropped*: they are left at their existing 'spatial_group_id' (by default, from 'build_site_table', a grid-snapped

| Param | Required | Default | Doc |
|---|---|---|---|
| sites | yes |  | Data frame with one row per observation, containing at least 'id_col', 'lat_col', and 'lon_col'. Typically the output of 'build_site_table', which already carries 'spatial_group_id'/'spatial_group_N'/'is_default_group' defaults - this function *updates those columns in place* for whichever observations get captured by a drawn box, leaving everything else untouched. 'is_default_group' (not the contents of 'spatial_group_id' itself) is what this function checks to decide which rows are still eligible to be captured by a new box - so it works the same way regardless of what 'build_site_table()''s default label happens to look like. If 'sites' has no 'spatial_group_id'/'spatial_group_N' columns at all (i.e. it did not come from 'build_site_table()'), singleton defaults are initialized first, with a message. If 'sites' has 'spatial_group_id'/'spatial_group_N' but no 'is_default_group' (a site table built before this marker existed), it is inferred from the old default convention, with a message. id_col: Character. Column identifying each observation. Default '"observation_id"'. |
| id_col | no | "observation_id" |  |
| lat_col | no | "lat" | Character. Latitude/longitude column names. Default '"lat"' / '"lon"'. tile: Character. Leaflet tile provider, passed to 'define_search_polygon'. Default '"Esri.OceanBasemap"'. |
| lon_col | no | "lon" | Character. Latitude/longitude column names. Default '"lat"' / '"lon"'. tile: Character. Leaflet tile provider, passed to 'define_search_polygon'. Default '"Esri.OceanBasemap"'. |
| tile | no | "Esri.OceanBasemap" |  |

**Value:** 'sites' with 'spatial_group_id'/'spatial_group_N'/ 'is_default_group' updated in place: observations captured by a drawn box (in draw order; an observation falling inside more than one box gets the *most recently drawn* one, with a warning - see Details) get '"spatial_group_1"', '"spatial_group_2"', ..., 'spatial_group_N' equal to that group's member count, and 'is_default_group = FALSE'. Observat

### investigate_flagged_accession(accession, species = NULL, max_related = 30L, method = c("remote", "local"), database = "nt", score_range = 8, min_score = 70, max_hits = 20L, submission_window = 5L, min_coverage = 0.5, max_length_ratio = 3, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), inconclusive_ttl_days = 30, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), verbose = TRUE)

Deep-Dive Verification for a Single Flagged Reference Accession

For ONE accession 'evaluate_reference_accessions()' flagged (typically '"incongruent"'), runs two targeted, more expensive comparisons than that broad-scan function ever attempts - deliberately meant to run only on the small subset a caller has already decided is worth a closer look, not at production scale.

| Param | Required | Default | Doc |
|---|---|---|---|
| accession | yes |  | Character scalar. The flagged accession to investigate. species: Character or 'NULL' (default). The accession's own listed species - if 'NULL', fetched from its real GenBank record. |
| species | no | NULL |  |
| max_related | no | 30L | Integer (default '30L'). Caps how many conspecific/ disagreeing-taxon accessions are fetched and compared against, for each of the two comparisons - a deliberate bound, not exhaustive reference-database compilation (see 'TaxaLikely::fetch_ncbi_reference_sequences()' for that). |
| method | no | c("remote", "local") | Passed to BOTH the disagreeing-taxon re-BLAST AND the two '.blast_against_comparison_set()' comparisons (self-consistency, cross-taxon) - see 'blast_sequences()'. |
| database | no | "nt" | Passed to BOTH the disagreeing-taxon re-BLAST AND the two '.blast_against_comparison_set()' comparisons (self-consistency, cross-taxon) - see 'blast_sequences()'. |
| score_range | no | 8 | Passed only to the disagreeing-taxon re-BLAST - see 'blast_sequences()'. The two comparison-set BLAST calls use their own internal, deliberately permissive values (see '.blast_against_comparison_set()'), since they exist to honestly report every comparison-set accession's real identity/coverage, not to apply a score-window cutoff. |
| min_score | no | 70 | Passed only to the disagreeing-taxon re-BLAST - see 'blast_sequences()'. The two comparison-set BLAST calls use their own internal, deliberately permissive values (see '.blast_against_comparison_set()'), since they exist to honestly report every comparison-set accession's real identity/coverage, not to apply a score-window cutoff. |
| max_hits | no | 20L | Passed only to the disagreeing-taxon re-BLAST - see 'blast_sequences()'. The two comparison-set BLAST calls use their own internal, deliberately permissive values (see '.blast_against_comparison_set()'), since they exist to honestly report every comparison-set accession's real identity/coverage, not to apply a score-window cutoff. |
| submission_window | no | 5L | Integer (default '5L'). Same-submission-batch independence-filter window, matching 'evaluate_reference_accessions()''s own default. |
| min_coverage | no | 0.5 | Numeric (default '0.5'). Passed to '.blast_against_comparison_set()' - see that function's own documentation. Comparisons below this floor are retained in the output (never silently dropped) but excluded from the printed headline mean/range. |
| max_length_ratio | no | 3 | Numeric (default '3'). Passed to '.search_species_accessions()' - REQUIRED for correctness, not an optional tuning knob (see that function's own @section Length-ratio pre-filter, added 2026-08-08 after live testing against the real 'MZ605481' case found a plain NCBI organism-name search can be dominated by whole-genome-assembly records for a species with a published reference genome, leaving almost no length-comparable candidates in the raw result at all). |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | Character or 'NULL'. Default 'tools::R_user_dir("TaxaMatch", "cache")'. Set 'NULL' to disable caching entirely (every call re-investigates from scratch). See @section Caching above. |
| inconclusive_ttl_days | no | 30 | Numeric (default '30'). See @section Caching above. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | As in 'evaluate_reference_accessions()'. |
| verbose | no | TRUE | As in 'evaluate_reference_accessions()'. |

**Value:** A list: 'accession', 'listed_species' As given/discovered. 'conspecific_comparison' data.frame(accession, pident, coverage, meets_min_coverage, create_date) - one row per real conspecific accession BLAST actually returned a hit for. ALWAYS check 'coverage'/'meets_min_coverage' before trusting 'pident' - a high 'pident' at low coverage is not meaningful evidence of anything, see 'min_coverage' abov

### investigate_flagged_accessions(accessions, species = NULL, max_related = 30L, method = c("remote", "local"), database = "nt", score_range = 8, min_score = 70, max_hits = 20L, submission_window = 5L, min_coverage = 0.5, max_length_ratio = 3, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), inconclusive_ttl_days = 30, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), verbose = TRUE)

Deep-Dive Verification for a Batch of Flagged Reference Accessions

The natural 'investigate_flagged_accessions()' (plural) batch wrapper 'investigate_flagged_accession()''s own docs point at (Question 3, item 2): runs the identical per-accession investigation over a whole list, but shares a single in-memory NCBI-search lookup across the batch (so a 'listed_species' or 'disagreeing_taxon' repeated across several independently-flagged accessions is only fetched from NCBI once, not once per accession) and shares the same persistent cache 'investigate_flagged_accession()' itself uses - calling this after already having called 'investigate_flagged_accession()' on 

| Param | Required | Default | Doc |
|---|---|---|---|
| accessions | yes |  | Character vector of flagged accessions to investigate. Not deduplicated automatically (each is looked up in the persistent cache independently, so a duplicate is cheap - a cache hit after the first occurrence - rather than an error). species: Character vector the same length as 'accessions', or 'NULL' (default, every accession's species is fetched from its own GenBank record). A single accession's own override may be 'NA' to fall back to fetching that one accession's species while other elements stay overridden. |
| species | no | NULL |  |
| max_related | no | 30L |  |
| method | no | c("remote", "local") |  |
| database | no | "nt" |  |
| score_range | no | 8 |  |
| min_score | no | 70 |  |
| max_hits | no | 20L |  |
| submission_window | no | 5L |  |
| min_coverage | no | 0.5 |  |
| max_length_ratio | no | 3 |  |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") |  |
| inconclusive_ttl_days | no | 30 |  |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") |  |
| verbose | no | TRUE |  |

**Value:** A named list (names = 'accessions'), one element per accession, each in the same shape 'investigate_flagged_accession()' returns.

### join_event_site_metadata(detections, site_metadata, event_col = "event_id", id_col = "observation_id", lat_col = "lat", lon_col = "lon", observed_on_col = "observed_on", control_samples = NULL)

Join Event-Level Detections to a Site Metadata Table

Produces a 'site_df' suitable for 'build_site_table' from any event-level detections table (one row per 'id_col' x 'event_col' pair actually observed) and a separately-maintained site metadata table ('event_col' plus site attributes). This is the same underlying operation for every data-type pathway that lacks embedded site info - DNA/BLAST (Reads-table sample columns) and acoustic (recording/ device identifiers) both reduce to "join an event identifier against a metadata table of where/when that event happened" - so one function serves both rather than duplicating the join per pathway.

| Param | Required | Default | Doc |
|---|---|---|---|
| detections | yes |  | Data frame. One row per '(id_col, event_col)' pair that was actually observed - e.g. a Reads-table already pivoted to long format and filtered to 'n_reads > 0' (DNA/BLAST), or a BirdNET match object's own 'observation_id'/'source_file' pairs (acoustic, already one row per detection window). Must contain 'id_col' and 'event_col'. |
| site_metadata | yes |  | Data frame maintained separately from the detections table - one row per 'event_col' value, with at least 'lat_col'/'lon_col' columns and optionally 'observed_on_col'. This is the same kind of lookup table already used to identify blank/control samples (e.g. 'BLANKS_MARCH', 'BLANKS_AUG' in 'PtConceptionWorkflow_12S.R'), generalized to carry site coordinates and collection date instead of (or in addition to) blank status. |
| event_col | no | "event_id" | Character. Join key column name, present in both 'detections' and 'site_metadata'. Default '"event_id"'. id_col: Character. Observation ID column in 'detections'. Default '"observation_id"'. |
| id_col | no | "observation_id" |  |
| lat_col | no | "lat" | Character. Latitude/longitude column names in 'site_metadata'. Default '"lat"' / '"lon"'. |
| lon_col | no | "lon" | Character. Latitude/longitude column names in 'site_metadata'. Default '"lat"' / '"lon"'. |
| observed_on_col | no | "observed_on" | Character. Collection-date column name in 'site_metadata', or 'NULL' if not available. Default '"observed_on"'. |
| control_samples | no | NULL | Character vector of 'event_col' values to exclude before joining (blanks/controls are not real site detections). Default 'NULL' (no exclusion). |

**Value:** A tibble in the long-format shape 'build_site_table''s 'site_df' argument expects: 'id_col', 'lat', 'lon', 'observed_on' ('NA' if 'observed_on_col = NULL'), plus 'event_col' retained for traceability. May have more than one row per 'id_col' value - this is the correct shape for an 'id_col' value (e.g. a sequence ASV) genuinely detected at more than one real event's site. Rows whose 'event_col' val

### match_driving_accessions(match_df, score_col = "score_original", obs_col = "observation_id", species_col = "species", accession_col = "accession")

Which Reference Accessions Ever Drive a Likelihood?

Returns the accessions that are the max-scoring accession of their species for at least one observation (ties kept). 'TaxaLikely::evaluate_likelihoods()' reads the per-species best match, so every other accession never drives a likelihood and no verdict on it can change an assignment. This is a COST FILTER for the BLAST screen ('evaluate_reference_accessions()'), not a change to the match object: on the real PtConception 12S match object it keeps 709 of 995 candidate accessions.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. A standardized match object with the four columns named below. |
| score_col | no | "score_original" | Character. Column names; defaults '"score_original"', '"observation_id"', '"species"', '"accession"'. |
| obs_col | no | "observation_id" | Character. Column names; defaults '"score_original"', '"observation_id"', '"species"', '"accession"'. |
| species_col | no | "species" | Character. Column names; defaults '"score_original"', '"observation_id"', '"species"', '"accession"'. |
| accession_col | no | "accession" | Character. Column names; defaults '"score_original"', '"observation_id"', '"species"', '"accession"'. |

**Value:** Character vector of accessions, exactly as they appear in 'match_df' (version suffixes untouched, so they key the same cache rows a plain 'unique(match_df$accession)' would), unique, in first-appearance order.

### migrate_reference_cache(cache_dir, to_key = NULL, from_key = NULL, verbose = TRUE)

Migrate a Reference-Accession Cache to a New params_key

'evaluate_reference_accessions()' stamps every cached row with one global 'params_key' (its verdict-affecting arguments plus an internal cache version). Bumping that version - as the 2026-09-03 switch to the primer-stripped 'query_span = "amplicon"' did ('"v5_amplicon_query"') - invalidates every existing row: ~3,000 real ones (PtConception 995; GreatLakes 1060 + 280 + 690). This helper rewrites the key on the rows the change cannot have altered, so only the rest re-BLAST.

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | yes |  | Character. The directory holding 'reference_accession_cache.rds'. to_key: Character or 'NULL' (default). The 'params_key' to migrate to. 'NULL' uses the key 'evaluate_reference_accessions()''s own current defaults produce (built by the same internal code the function uses). If you screen with non-default verdict-affecting arguments ('top_n', 'max_hits', ...), pass the key your call produces - read it off 'params_key' in a row that call has written. |
| to_key | no | NULL |  |
| from_key | no | NULL | Character vector or 'NULL' (default). Which existing keys to migrate from. 'NULL' means every key other than 'to_key'. verbose: Logical (default 'TRUE'). Print the counts. |
| verbose | no | TRUE |  |

**Value:** Invisibly, a list: 'to_key', 'n_carried_forward' (rows rewritten), 'n_left_to_reevaluate' (rows under 'from_key' NOT rewritten, by flag in 'left_by_flag'), 'n_already_current', 'backup_path'.

### read_animl_output(files, file_col = "FileName", species_col = "prediction", score_col = "confidence", common_name_col = NULL, n_candidates = NULL, min_confidence = 0, top_n = NULL, bbox_cols = NULL)

Read Animl Camera Trap Results into a Match Object

Reads one or more Animl (MegaDetector + SpeciesNet) result CSV files and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Paths to Animl result CSV files. Alternatively, a path to a directory: all *.csv files in that directory (non-recursive) are read. |
| file_col | no | "FileName" | Character. Name of the column containing the image file path or filename. Default '"FileName"' (Animl R package manifest format). |
| species_col | no | "prediction" | Character. Name of the column containing the species prediction (scientific name). Default '"prediction"'. For wide-format outputs (multiple candidates per row), set 'n_candidates' and this argument becomes the prefix (e.g., '"pred"' for 'pred1', 'pred2', ...). |
| score_col | no | "confidence" | Character. Name of the confidence column. Default '"confidence"'. For wide-format outputs, this is used as the prefix (e.g., '"score"' for 'score1', 'score2', ...). |
| common_name_col | no | NULL | Character or 'NULL'. Name of a common name column, if present. Default 'NULL' (common name column set to 'NA'). |
| n_candidates | no | NULL | Integer or 'NULL'. If 'NULL' (default), expects *long format* — one row per image × candidate species, with 'species_col' and 'score_col' holding the prediction and confidence directly. If a positive integer, expects *wide format* — one row per image crop with candidate columns named 'paste0(species_col, 1:n_candidates)' and 'paste0(score_col, 1:n_candidates)' (e.g., 'pred1'/'score1' through 'pred3'/'score3'). The wide format is pivoted to long before filtering. |
| min_confidence | no | 0 | Numeric. Detections below this confidence are dropped. Default '0' (keep all). top_n: Integer or 'NULL'. If supplied, only the top 'n' candidates (by confidence) within each image are retained. Default 'NULL' (keep all). |
| top_n | no | NULL |  |
| bbox_cols | no | NULL | Character vector of length 2 or 'NULL'. Names of the bounding-box *width* and *height* columns (normalized 0-1, as output by MegaDetector). Supply as a named vector 'c(w = "bbox_w", h = "bbox_h")' or positionally 'c("bbox_w", "bbox_h")'. When provided, 'coverage = bbox_w * bbox_h' is computed and added to the output; this area fraction serves as an image-quality analog to BLAST 'qcovs' and is accepted by 'TaxaLikely::evaluate_likelihoods(min_coverage=)'. Default 'NULL' (no coverage column). |

**Value:** A data frame with one row per image × candidate species, containing: 'observation_id' Unique identifier derived from the image filename stem (path stripped, extension(s) stripped). Multiple rows with the same 'observation_id' represent alternative species candidates for the same image/crop — analogous to multiple BLAST hits per eDNA query or multiple BirdNET candidates per time window. 'score' Ani

### read_birdnet_output(files, min_confidence = 0, top_n = NULL)

Read BirdNET-Analyzer Results into a Match Object

Reads one or more BirdNET-Analyzer result CSV files and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector of paths to BirdNET result CSV files (typically named 'recording.BirdNET.results.csv'); a path to a directory (all *.BirdNET.results.csv files are read non-recursively); or a data frame already loaded into R. The data frame path accepts both the original BirdNET column names ('"Start (s)"', '"Scientific name"', etc.) and the R-mangled versions produced by 'read.csv()' with 'check.names = TRUE' ('"Start..s."', '"Scientific.name"', etc.). A '"File"' column must be present (Gradio / web interface combined-CSV format) to derive 'observation_id' stems; CLI per-recording CSVs should be passed as file paths rather than pre-loaded data frames. |
| min_confidence | no | 0 | Numeric. Detections below this confidence are dropped. Default '0' (keep all). BirdNET's own default threshold is '0.1'. top_n: Integer or 'NULL'. If supplied, only the top 'n' detections (by confidence) within each time window are retained. Default 'NULL' (keep all detections per window). Setting 'top_n = 1' retains only the best species per window; 'top_n = 3' reproduces BirdNET's default output when the tool is run with --top_n 3. |
| top_n | no | NULL |  |

**Value:** A data frame with one row per file × time-window × detected species, containing: 'observation_id' Unique identifier combining file stem and time window: '"{file_stem}_{start_s}-{end_s}"', with 'start_s'/'end_s' formatted to a fixed 1 decimal place so the same window produces the same ID across platforms/R versions. Pass as 'observation_id_col' to 'standardize_match_data()'. 'score' BirdNET confide

### read_inaturalist_cv_output(files, score_type = c("combined_score", "score"), min_confidence = 0, top_n = NULL)

Read iNaturalist Computer Vision API Results into a Match Object

Reads one or more saved JSON files from the iNaturalist computer vision API and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Paths to iNaturalist CV JSON files. Alternatively, a path to a directory: all *.json files in that directory (non-recursive) are read. |
| score_type | no | c("combined_score", "score") | Character. Which score to use from the API response. '"combined_score"' (default) incorporates community identification frequency and is generally more calibrated. '"score"' is the raw computer-vision softmax score. |
| min_confidence | no | 0 | Numeric. Detections below this score are dropped. Default '0' (keep all). top_n: Integer or 'NULL'. If supplied, only the top 'n' candidates (by score) within each image are retained. Default 'NULL' (keep all). |
| top_n | no | NULL |  |

**Value:** A data frame with one row per image x candidate taxon, containing: 'observation_id' Unique identifier derived from the JSON filename stem (the name you gave the saved response file, ideally the image filename stem). 'score' iNaturalist CV score, passed through unchanged from the saved JSON's 'score_type' field. The live API returns scores on iNaturalist's 0-100 softmax convention (candidates for o

### read_sequence_table(input_data, sequence_col = "sequence", observation_id_col = NULL, abundance_cols = NULL, taxonomy = NULL, header_format = "none", id_prefix = "ASV")

Read Sequence Data into a Tidy ASV Table

Converts a DADA2 sequence table (matrix), a FASTA file, or a data frame (e.g., from a sequencing provider's CSV) into a tidy data frame with one row per unique sequence.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_data | yes |  | One of: • A DADA2 sequence table (matrix with samples as rows and DNA sequences as column names) • A path to a FASTA file • A 'DNAStringSet' object from Biostrings • A data frame containing at least a 'sequence' column (e.g., output from a sequencing provider). See Details for how abundance is computed. |
| sequence_col | no | "sequence" | For data frame input: name of the column containing DNA sequences. Default '"sequence"'. Matching is case-insensitive (all column names are lowercased internally for matching), though the returned columns other than the four core ones are lowercased in the output regardless of their original casing in 'input_data'. |
| observation_id_col | no | NULL | For data frame input: name of an existing observation/ESV identifier column to use as 'asv_id'. If 'NULL' (default), sequential IDs are generated using 'id_prefix'. |
| abundance_cols | no | NULL | For data frame input: character vector of column names containing per-sample read counts to sum for total abundance. If 'NULL' (default), numeric columns that are not taxonomy or metadata are auto-detected against an internal exclusion list (case-insensitive exact match against standard taxonomy ranks plus common ID/score column names - see '.non_abundance_col_names' in the package source for the exact list). If no abundance columns are found, abundance is set to 1 per row. A 'message()' reports which columns were summed (or that none were found), so unexpected auto-detection results can be diagnosed without inspecting the code. |
| taxonomy | no | NULL | Optional data frame with taxonomy for each sequence. Must contain a column named '"sequence"' (for DADA2/DNAStringSet input, matched against the sequence itself) or '"accession"' (for FASTA input, matched against the header's first whitespace-delimited token). See Details. Ignored for data frame input (taxonomy columns are retained directly). |
| header_format | no | "none" | For FASTA input only: how to parse taxonomy from sequence headers. '"semicolon"' expects 'accession;kingdom;phylum;class;order;family;genus;species'. '"none"' (default) does not parse headers. |
| id_prefix | no | "ASV" | Character prefix for generated ASV identifiers. Default '"ASV"'. |

**Value:** A data frame with columns: asv_id Unique identifier (e.g., "ASV_001") sequence DNA sequence string length Sequence length in base pairs abundance Total read count across all samples If taxonomy is provided (via 'taxonomy' argument, parsed from FASTA headers, or present in a data frame input), taxonomy columns are appended. For FASTA/'DNAStringSet' input with 'header_format = "none"' (the default),

### read_speciesnet_output(files, min_confidence = 0, top_n = NULL, include_coverage = FALSE, min_detection_conf = 0)

Read SpeciesNet Batch Classification Results into a Match Object

Reads one or more real SpeciesNet CLI ('google/cameratrapai', python -m speciesnet.scripts.run_model --predictions_json=...) batch prediction JSON files and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Paths to SpeciesNet 'predictions_json' output files. Alternatively, a path to a directory: all *.json files in that directory (non-recursive) are read. A single file's top-level 'predictions' array may cover many images. |
| min_confidence | no | 0 | Numeric. Candidates below this classification score are dropped. Default '0' (keep all). top_n: Integer or 'NULL'. If supplied, only the top 'n' candidates (by score) per image are retained - SpeciesNet's own classifier already returns at most 5. Default 'NULL' (keep all up to 5). |
| top_n | no | NULL |  |
| include_coverage | no | FALSE | Logical. If 'TRUE', adds a 'coverage' column (bounding-box area fraction, 'bbox_w * bbox_h') and a 'detection_conf' column, taken from the image's highest-confidence MegaDetector '"animal"' detection (SpeciesNet detection category '"1"') - an image-quality analog to BLAST 'qcovs', matching 'read_animl_output()''s 'bbox_cols' convention. 'NA' for images with no qualifying detection. Default 'FALSE'. |
| min_detection_conf | no | 0 | Numeric. Only used when 'include_coverage = TRUE': detections below this MegaDetector confidence are not eligible to be the representative detection. Default '0'. |

**Value:** A data frame with one row per image x candidate species, containing: 'observation_id' Unique identifier derived from the image filename stem ('filepath', path stripped, extension(s) stripped). 'score' SpeciesNet classifier confidence (0-1) for this candidate, from the RAW top-5 'classifications' block - pre-geofencing, pre-taxonomic-rollup. This is deliberately NOT the same as 'ensemble_prediction

### refine_reference_verdicts(evaluation, cache_dir = NULL, pair_table = NULL, rank_system = TaxaTools::standard_ranks, min_congruent_rank = "family", top_n = 5L, hierarchy_incongruent_threshold = 0.5, min_independent_partners = 3L, min_partner_weight = 0, max_iter = 10L, tol = 1e-04, verbose = TRUE, local_corroboration = NULL, ...)

Re-run Reference Verdicts With Each Partner Weighted by Its Own Trustworthiness

'evaluate_reference_accessions()''s verdict is a vote over an accession's closest independent BLAST neighbours in which every neighbour counts exactly once, however dubious that neighbour's own label is. This function re-runs that vote from the cached per-partner votes, scaling each partner's contribution by its own 'label_confidence', and iterates to a fixpoint - because discounting a partner changes both the numerator and the denominator of everyone else's vote, which can flip verdicts in both directions.

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluation | yes |  | Data frame. Output of 'evaluate_reference_accessions()'. 'label_confidence'/'reference_action' are computed via 'score_reference_labels()' if absent. |
| cache_dir | no | NULL | Character or 'NULL'. The same 'cache_dir' 'evaluate_reference_accessions()' was called with; its 'reference_pair_cache.rds' supplies the per-partner votes. Ignored when 'pair_table' is supplied directly. |
| pair_table | no | NULL | Data frame or 'NULL'. The per-partner votes, if held in memory rather than on disk - columns 'id_x', 'id_y', 'p_match' (0-1), 'pair_finest_common_rank'. |
| rank_system | no | TaxaTools::standard_ranks | Character vector (default 'TaxaTools::standard_ranks'), coarse to fine - must be the ladder the pair table's 'pair_finest_common_rank' was computed against. |
| min_congruent_rank | no | "family" |  |
| top_n | no | 5L |  |
| hierarchy_incongruent_threshold | no | 0.5 |  |
| min_independent_partners | no | 3L |  |
| min_partner_weight | no | 0 | Numeric (default '0'). Floor on a discounted partner's weight; '0' means an accession resolved to 'reference_action == "remove"' stops voting entirely. |
| max_iter | no | 10L | Integer (default '10L'). Iteration cap. tol: Numeric (default '1e-4'). Converged when no accession's 'label_confidence' moves by more than this. verbose: Logical (default 'TRUE'). |
| tol | no | 1e-04 |  |
| verbose | no | TRUE |  |
| local_corroboration | no | NULL | Data frame or 'NULL' (default). Forwarded to 'score_reference_labels()'; the same veto (a locally-corroborated '"remove"' becomes '"inspect"') is applied to 'reference_action_trust'. ...: Passed to 'score_reference_labels()' ('margin_scale', 'margin_cap', the three action thresholds) - use the SAME values here as anywhere else in a pipeline, or the refined and unrefined columns are not comparable. |
| ... | yes |  |  |

**Value:** 'evaluation' with these columns added: 'hierarchy_flag_trust', 'label_confidence_trust', 'reference_action_trust', 'frac_below_min_congruent_rank_trust', 'n_effective_partners' (the weighted partner count, which is what 'min_independent_partners' is now compared against), and 'trust_refined' (logical - 'FALSE' where no pair data existed, in which case the *_trust columns simply repeat the unrefine

### remove_incongruent_references(match_df, evaluation, remove_insufficient_evidence = FALSE, override_accessions = NULL, gate = c("action", "flag"))

Remove Confidently-Incongruent Reference Accessions from a Match Object

Filters a match data frame to remove rows whose reference accession was flagged '"incongruent"' by 'evaluate_reference_accessions()'. Deliberately conservative: only the confident '"incongruent"' verdict is dropped by default - '"insufficient_independent_evidence"' is ambiguous (may simply mean a sparsely-referenced region of the database, not a real problem) and is retained unless 'remove_insufficient_evidence = TRUE'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. A standardized match object (from 'standardize_match_data()') containing an 'accession' column. |
| evaluation | yes |  | Data frame. Output of 'evaluate_reference_accessions()'. |
| remove_insufficient_evidence | no | FALSE | Logical (default 'FALSE'). If 'TRUE', also removes accessions flagged '"insufficient_independent_evidence"'. Applies under both 'gate' settings - 'reference_action' can never be '"remove"' for that flag on its own (see 'score_reference_labels()''s @section Why "remove" also requires no corroboration anywhere), so this argument stays the only way to drop them. |
| override_accessions | no | NULL | Character vector of accession IDs (default 'NULL'), or 'NULL' to disable. Accessions listed here are NEVER removed, regardless of 'hierarchy_flag' - the automated counterpart to the @section Use flag_incongruent_references() first caution above. 'hierarchy_flag = "incongruent"' alone cannot distinguish a genuine mislabel from a correctly-labeled record with poor marker resolution or thin corroborating coverage (a real confirmed case in this ecosystem: Stereolepis doederleini was flagged '"incongruent"' by a broad screen, then separately investigated and found to be exactly this - not a real mislabel). 'resolve_review_overrides()' derives this argument automatically from 'review_flagged_accessions()''s LLM second-look verdicts, so a caller can safely default to removing every flagged accession while still letting a specific, reviewed explanation override that default for the one accession it actually applies to - rather than choosing between "remove everything, including real correctly- labeled records" and "remove nothing, unreviewed." Only ever rescues, never removes an accession 'hierarchy_flag' would otherwise have kept. gate: Character, '"action"' (default) or '"flag"'. '"action"' removes accessions whose 'reference_action' is '"remove"'; '"flag"' removes every accession whose 'hierarchy_flag' is '"incongruent"', the pre-2026-09-02 behaviour. Under '"action"', 'reference_action' is computed on the fly via 'score_reference_labels()' if 'evaluation' does not already carry it. |
| gate | no | c("action", "flag") |  |

**Value:** The input 'match_df' with flagged rows removed. Unchanged if no flagged accessions are found.

### report_match(match_data, data_type = NULL, verbose = FALSE)

Generate a Report Section for Sequence Matching

Summarizes the match data produced by TaxaMatch into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_data | yes |  | Data frame. Match results from 'blast_sequences' or 'standardize_match_data'. Must contain at least 'observation_id' and 'score_original' - the canonical raw score column name produced by 'standardize_match_data()' (see the package's "Canonical Match Object" documentation), not 'score'. A 'match_data' lacking 'score_original' is accepted without error but produces no score statistics and empty results text. |
| data_type | no | NULL | Character or 'NULL'. One of '"eDNA"', '"image"', '"acoustic"'. If 'NULL', auto-detected as '"eDNA"' when 'match_data' has an 'accession' or 'alignment_length' column (both BLAST-specific); otherwise stays 'NULL' and the methods/results text uses generic wording. There is currently no auto-detection for '"image"'/'"acoustic"' - pass these explicitly. 'data_type' also controls whether the results text formats scores as a percentage (see '@return''s 'results' entry). verbose: Logical. Print summary messages. Default 'FALSE'. |
| verbose | no | FALSE |  |

**Value:** A 'report_section' object with: methods Template text describing matching approach. results Template text summarizing match statistics, or 'NULL' when 'match_data' has neither 'score_original' nor a taxon-name column to summarize. Scores are formatted as a percentage only when 'data_type == "eDNA"' (percent identity is always 0-100 for BLAST); for '"image"'/'"acoustic"' (whose score scale varies b

### resolve_review_overrides(review_result, keep_explanations = c("poor_marker_resolution", "sister_family_thin_coverage", "hybrid_or_specimen_code_artifact"), min_confidence = c("high", "moderate"))

Derive Removal Overrides from an LLM Second-Look Review

Bridges 'review_flagged_accessions()''s LLM-based second-look verdicts to 'remove_incongruent_references()''s 'override_accessions' argument, automating a "remove everything flagged by default, but let a specific reviewed explanation override that default for the one accession it actually applies to" pipeline - rather than choosing between removing every flagged accession (including real, correctly-labeled records the raw BLAST verdict can't distinguish from a genuine mislabel) or removing nothing until every flag has been manually reviewed.

| Param | Required | Default | Doc |
|---|---|---|---|
| review_result | yes |  | Data frame. Output of 'review_flagged_accessions()' (must have 'accession', 'accession_likely_explanation', 'accession_review_confidence' columns). |
| keep_explanations | no | c("poor_marker_resolution", "sister_family_thin_coverage", "hybrid_or_specimen_code_artifact") | Character vector (default 'c("poor_marker_resolution", "sister_family_thin_coverage", "hybrid_or_specimen_code_artifact")') - the 'accession_likely_explanation' values that should override an automatic removal. Deliberately excludes '"uncertain"' from the default: an LLM verdict that is ITSELF uncertain should not automatically override a hard BLAST-based '"incongruent"' flag - pass '"uncertain"' explicitly if you want to trust it too. '"genuine_mislabel"' is never included (that verdict CONFIRMS removal, it never overrides it). |
| min_confidence | no | c("high", "moderate") | Character vector (default 'c("high", "moderate")'). Only a 'accession_review_confidence' value in this set is trusted as an override - a '"low"'-confidence review falls through to removal (the same conservative-default behavior as an unreviewed accession), even if its 'accession_likely_explanation' is in 'keep_explanations'. |

**Value:** Character vector of accessions to pass directly as 'remove_incongruent_references(override_accessions = ...)'.

### review_flagged_accessions(evaluated_df, hierarchy_flags = c("incongruent", "insufficient_independent_evidence"), include_non_species_resolved = TRUE, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), taxa_per_call = 10L, max_tokens = NULL, max_retries = 2L, pause_seconds = 1, verbose = TRUE, local_min_overlap = NULL)

LLM Second-Look Review of Flagged Reference Accessions

Sends 'evaluate_reference_accessions()''s flagged/borderline rows to an LLM for a free-text second look - the same "narrative-judgment layer added ON TOP of statistical flags, never replacing them, never auto-acting" pattern 'TaxaFlag::review_assignments()' already established for posterior taxonomic assignments (implements Question 2 of 'ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md'). The LLM never re-decides 'hierarchy_flag' - it adds what the statistical check structurally cannot: recognizing a known hybrid-cross name (e.g. '"Ctenopharyngodon idella x Megalobrama amblyceph

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluated_df | yes |  | Data frame - 'evaluate_reference_accessions()''s own output. Must contain 'accession', 'listed_taxon', 'hierarchy_flag', one row per accession. Every other column used in the prompt ('finest_common_rank', 'best_agreeing_pident', 'best_disagreeing_pident', 'best_disagreeing_taxon', 'congruent_evidence_exists_anywhere', 'congruent_evidence_best_pident', 'taxonomy_resolution_source', 'listed_taxon_is_species', 'n_independent_top_matches', 'n_top_matches_available', 'frac_independent_below_min_congruent_rank') is optional - silently omitted from the prompt when absent, matching 'TaxaFlag::review_assignments()''s established convention for optional upstream columns. A duplicated 'accession' value triggers a 'warning()' (see Details) rather than an error, since a caller may have joined this onto a match object by mistake. |
| hierarchy_flags | no | c("incongruent", "insufficient_independent_evidence") | Character vector of 'hierarchy_flag' values to review. Default 'c("incongruent", "insufficient_independent_evidence")'. |
| include_non_species_resolved | no | TRUE | Logical (default 'TRUE'). Also review any row with 'listed_taxon_is_species == FALSE', regardless of 'hierarchy_flag' - a structurally different, orthogonal problem the evaluation guide documents separately (see its own "listed_taxon_is_ species = FALSE" section). Silently ignored if 'listed_taxon_is_species' is absent from 'evaluated_df'. |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | Character or 'NULL'. Default 'tools::R_user_dir("TaxaMatch", "cache")' (same default/convention as 'evaluate_reference_accessions()' and 'investigate_flagged_accession()'). Persistent, accession-keyed cache of LLM reviews - an accession already reviewed with UNCHANGED inputs (see @section Caching below) is served from cache instead of making a real LLM call. Set 'NULL' to disable caching entirely (every call re-reviews every in-scope accession, the pre-2026-08-14 behavior). llm_fn: Function. LLM provider function with signature function(prompt_str, ...). Default 'TaxaTools::call_api'. *Known footgun:* 'call_api()''s provider auto-detection is set up by TaxaTools's own '.onAttach()', which only runs via 'library(TaxaTools)' - a fully-namespaced call (TaxaTools:: everywhere, no 'library()') never triggers it, and 'call_api()' silently falls back to degraded/uniform output rather than erroring. Pass 'llm_fn' explicitly if every review comes back suspiciously uniform, e.g. 'function(p) TaxaTools::call_api(p, provider = "anthropic")'. See 'TaxaID/CLAUDE.md''s "Known R Footguns" for the full record. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) |  |
| taxa_per_call | no | 10L | Integer. Maximum accessions per LLM call. Default '10L'. |
| max_tokens | no | NULL | Integer or 'NULL'. Forwarded as 'llm_fn(prompt, max_tokens = max_tokens)' whenever supplied. Default 'NULL' - 'llm_fn''s own default applies. |
| max_retries | no | 2L | Integer (default '2L'). A truncated, empty, or unparseable batch response is automatically split in half and retried (a smaller batch requests a proportionally shorter response) up to this many times, matching 'review_assignments()''s own retry mechanism. |
| pause_seconds | no | 1 | Numeric (default '1'). Seconds to pause between LLM calls. verbose: Logical (default 'TRUE'). Print progress messages. |
| verbose | no | TRUE |  |
| local_min_overlap | no | NULL | Numeric in (0, 1] or 'NULL' (default). The 'min_overlap' 'corroborate_references_locally()' was run with, quoted in the prompt's local-corroboration line ("best identity X% over >= 80% of the amplicon"). 'NULL' reads it from 'attr(evaluated_df, "local_corroboration_params")' when 'score_reference_labels()' left one there, and otherwise words the line without a number. Only matters when 'evaluated_df' carries 'local_n_independent_conspecific'/'local_best_independent_pident'. |

**Value:** 'evaluated_df' with 4 columns appended ('NA' for out-of-scope rows): 'accession_likely_explanation' One of '"genuine_mislabel"', '"poor_marker_resolution"', '"sister_family_thin_coverage"', '"hybrid_or_specimen_code_artifact"', '"uncertain"' - the LLM's own categorization of WHY the accession was flagged, never a re-decided 'hierarchy_flag'. 'accession_review_confidence' '"high"' / '"moderate"' / 

### score_image_inat(image_path, lat = NULL, lng = NULL, observed_on = NULL, top_n = 10L, recursive = FALSE, api_token = Sys.getenv("INAT_API_TOKEN"))

Score images using the iNaturalist Computer Vision API

Submits one or more images to the iNaturalist CV API and returns a tidy match object with ranked taxon suggestions and associated scores. When latitude/longitude are supplied (via argument or EXIF), 'combined_score' reflects iNaturalist's geomodel prior; the ratio 'combined_score / vision_score' ('geo_prior_weight') recovers the implicit geographic prior weight for each taxon at that location. 'geo_prior_weight' is 'NA' when 'vision_score == 0' (a real case for taxa with very low vision-classifier confidence).

| Param | Required | Default | Doc |
|---|---|---|---|
| image_path | yes |  | Character. Path to a single JPEG or PNG image file, a character vector of image file paths, or a path to a directory. When a directory is given, all '.jpg', '.jpeg', and '.png' files are processed - non-recursively by default; set 'recursive = TRUE' to scan subdirectories. 'recursive' is silently ignored when 'image_path' is a file vector rather than a directory. lat: Numeric. Latitude in decimal degrees (optional). When supplied, this value is used for all images and overrides any EXIF-derived latitude. Must be supplied together with 'lng'. lng: Numeric. Longitude in decimal degrees (optional). When supplied, this value is used for all images and overrides any EXIF-derived longitude. Must be supplied together with 'lat'. |
| lat | no | NULL |  |
| lng | no | NULL |  |
| observed_on | no | NULL | Character. Observation date in '"YYYY-MM-DD"' format (optional). When supplied, used for all images and overrides EXIF-derived dates. top_n: Integer. Number of top taxon suggestions to return per image. Default '10L'. |
| top_n | no | 10L |  |
| recursive | no | FALSE | Logical. When 'image_path' is a directory, also scan subdirectories recursively. Default 'FALSE'. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. iNaturalist API token. Defaults to the 'INAT_API_TOKEN' environment variable. Obtain a token by visiting 'https://www.inaturalist.org/users/api_token' while logged in. |

**Value:** A tibble with up to 'top_n' rows per image (one per candidate taxon; some images may return fewer when the API has fewer suggestions), containing: 'observation_id' (image filename stem), 'taxon_name', 'taxon_name_rank', 'score_original' (identical to 'combined_score'; kept under the canonical pipeline name for compatibility with 'evaluate_likelihoods()'), 'genus', 'common_name', 'iconic_taxon_name

### score_reference_labels(evaluation, margin_scale = 1, margin_cap = 5, action_remove_below = 0.05, action_inspect_below = 0.25, action_caution_below = 0.75, overwrite = FALSE, local_corroboration = NULL)

Score Reference Labels: a Numeric Label Confidence and a Categorical Action

Adds two derived columns to an 'evaluate_reference_accessions()' result: 'label_confidence' (numeric, high = the listed label is more likely CORRECT) and 'reference_action' ('"keep"'/'"caution"'/'"inspect"'/ '"remove"'/'"untested"'). Evidence and action are deliberately separate columns - the same split this ecosystem already uses for 'TaxaFlag::observation_validity' (numeric) vs 'validity_flag' (categorical), and for 'TaxaHabitat::flag_institution_candidates()''s classify-then-review shape. The numeric grades the evidence; the categorical is for humans and for 'remove_incongruent_references()

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluation | yes |  | Data frame. Output of 'evaluate_reference_accessions()' (or any data frame carrying its diagnostic columns - a cache file read straight off disk works). |
| margin_scale | no | 1 | Numeric (default '1'). Percent-identity points per unit of log-odds. Larger = the identity margin matters less relative to the vote. See @section Where the numbers come from. |
| margin_cap | no | 5 | Numeric (default '5'). Caps \|d\|, and supplies the value used for the two one-sided cases (corroborated with nothing contradicting it; contradicted with nothing corroborating it anywhere). |
| action_remove_below | no | 0.05 | Numeric thresholds on 'label_confidence' (defaults '0.05', '0.25', '0.75') separating '"remove"'/'"inspect"'/'"caution"'/'"keep"'. |
| action_inspect_below | no | 0.25 | Numeric thresholds on 'label_confidence' (defaults '0.05', '0.25', '0.75') separating '"remove"'/'"inspect"'/'"caution"'/'"keep"'. |
| action_caution_below | no | 0.75 | Numeric thresholds on 'label_confidence' (defaults '0.05', '0.25', '0.75') separating '"remove"'/'"inspect"'/'"caution"'/'"keep"'. |
| overwrite | no | FALSE | Logical (default 'FALSE'). 'TRUE' recomputes and replaces 'label_confidence'/'label_identity_margin'/'reference_action' (and the local-corroboration columns) if they are already present; 'FALSE' errors instead, so a second call with different parameters can't silently produce a mixed-provenance table. |
| local_corroboration | no | NULL | Data frame or 'NULL' (default). Output of 'corroborate_references_locally()'. Joined by version-stripped accession. See @section Local corroboration. |

**Value:** 'evaluation' with seven columns added: 'label_confidence' Numeric in (0, 1). 'NA' for a row with no computed congruence at all ('"not_evaluated_oversized"', '"not_evaluated_wrong_marker"', or a fetch failure). *Named contract (2026-09-05 critical-fix-review finding C): this value CANNOT REACH 1*, by construction - the Jeffreys smoothing floors the disagreement fraction at '0.5/(n+1)', so even a pe

### standardize_match_data(data = NULL, observation_id_col, score_col, rank_system = NULL, coverage_col = NULL, col_map = NULL, lowercase_names = TRUE)

Standardize Raw Match Data to Canonical Match Object

Reads raw match data (from a data frame or file), renames the observation identifier and score columns to canonical names ('observation_id' and 'score_original'), auto-detects or validates taxonomic rank columns, and derives 'taxon_name' and 'taxon_name_rank' via 'TaxaTools::create_taxon_names()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| data | no | NULL | A data frame, a file path (character string), or 'NULL'. When 'NULL' an interactive file chooser ('file.choose()') opens. CSV ('.csv') and tab-delimited ('.tsv', '.txt') files are supported when a path is supplied. |
| observation_id_col | yes |  | Character. Name of the column that holds the unique query identifier (e.g. '"ESVId"' for MiFish eDNA output). |
| score_col | yes |  | Character. Name of the column holding the raw match score (e.g. '"PercMatch"'). Values may be on any numeric scale; normalisation is performed later in TaxaLikely. |
| rank_system | no | NULL | Character vector of taxonomic rank column names, listed broadest to finest (e.g. 'c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")'). Column matching is case-insensitive. When 'NULL' (default), rank columns are auto-detected by matching column names against a built-in list of standard rank names ('domain' through 'form'). |
| coverage_col | no | NULL | Character or 'NULL'. Name of a column containing an alignment or detection quality fraction (0-1 or 0-100 scale, e.g. '"qcovs"' for BLAST query coverage). When supplied, the column is renamed to 'coverage' in the canonical output. TaxaLikely's 'evaluate_likelihoods()' accepts 'min_coverage' to pre-filter candidates whose 'coverage' falls below a threshold before likelihood calculation. Default 'NULL' (no coverage column). col_map: Optional named character vector of additional column renames applied before the core standardisation step, via 'TaxaTools::rename_cols()'. Format: 'c("OldName" = "new_name")'. Useful when source files use non-standard column names that are not auto-detected. |
| col_map | no | NULL |  |
| lowercase_names | no | TRUE | Logical. When 'TRUE' (default), all column names in the output are converted to lowercase as the final step. This produces a fully consistent canonical object (e.g. 'kingdom', 'testid', 'accession') and avoids case-sensitivity surprises in downstream joins. Set to 'FALSE' to preserve original column name casing. |

**Value:** A data frame with at minimum: 'observation_id' Unique query identifier (renamed from 'observation_id_col'). 'score_original' Raw match score (renamed from 'score_col'). Preserved unchanged throughout the pipeline; downstream functions add 'score_norm', 'score_softmax', and 'score_likelihood' columns as transformations are applied. 'taxon_name' Most specific non-NA taxon name (derived). 'taxon_name

### verify_local_corroborations(cache_dir, max_corroborators = 2L, verbose = TRUE)

Audit thin locally-corroborated rows against their own corroborator's verdict

'"locally_corroborated"' (2026-09-03) skips BLASTing an accession entirely when the caller's own reference set already has an independent conspecific deposit for it - cached with TTL 'Inf' and exempt from 'refine_reference_verdicts()''s trust-weighted refinement, since the MATCH itself, once observed, is permanent. But the _corroborator's own label_ is exactly as falsifiable as any other accession's (this is the same 'KJ135626'/'MZ605481' shape 'verify_removal_candidates()' closed for the removal veto, showing up in a different, larger population). Nothing today ever asks whether a corroborato

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | yes |  | The same persistent cache directory 'evaluate_reference_accessions()' was called with. Required - a '"locally_corroborated"' verdict only ever exists inside a persistent cache (the skip mechanism has nothing to record it in otherwise). |
| max_corroborators | no | 2L | Integer (default '2L'). A '"locally_corroborated"' row resting on more than this many independent corroborators is left out of the audit entirely - many independent partners all being wrong the same way is implausible, matching 'verify_removal_candidates()''s identical threshold. verbose: Logical (default 'TRUE'). |
| verbose | no | TRUE |  |

**Value:** A data frame, one row per thin '"locally_corroborated"' accession: 'accession', 'listed_taxon', 'n_corroborators', 'local_corroborator_accession', 'corroborator_reference_action', 'corroborator_hierarchy_flag', and 'status' ('"flagged"' - the corroborator's own evidence reads something other than a clean '"keep"' or '"untested"'; '"clean"' - the corroborator has a real '"keep"' verdict; '"unchecke

### verify_removal_candidates(evaluation, ..., audit_max_hits = 100L, cache_dir = NULL, screen_corroborators = TRUE, verbose = TRUE)

Verify Removal Candidates Against a Wider Evidence Window

Re-evaluates ONLY the accessions an evaluation would actually remove, at a larger 'max_hits', and reports which of them stop being removable. Nothing is removed, nothing is written back to the production cache, and no verdict is overwritten - this is the pre-removal audit step, not a replacement for the screen.

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluation | yes |  | An 'evaluate_reference_accessions()' result. Needs 'accession' plus either 'reference_action' or the diagnostic columns 'score_reference_labels()' derives it from. ...: Forwarded to 'evaluate_reference_accessions()'. Must carry the production run's own verdict-affecting arguments (see above). |
| ... | yes |  |  |
| audit_max_hits | no | 100L | Integer (default '100L'). The wider window. Note that on real data 13 of 34 accessions were still saturated at 100, so a clean result here bounds the problem rather than closing it. |
| cache_dir | no | NULL | Directory for the audit's own cache, or 'NULL' (default) for no caching. Because 'max_hits' is in 'params_key' an audit can never overwrite a production row, but a separate directory keeps the production cache free of rows no production call will ever read. Also the cache 'screen_corroborators' reads/writes corroborator verdicts through, so corroborators already evaluated (production or a prior audit) are served free. |
| screen_corroborators | no | TRUE | Logical (default 'TRUE'). For a row spared on 1-2 corroborators (see the section below), also check those corroborators' OWN label via 'evaluate_reference_accessions()' - reusing an accession already present in 'evaluation' for free where possible - and surface a corroborator whose own 'reference_action' is neither '"keep"' NOR '"untested"' (i.e. '"caution"'/'"inspect"'/ '"remove"') as a stronger, separate warning; an '"untested"' corroborator is deliberately NOT flagged - no usable evidence about it is not evidence AGAINST it. Never un-spares a row automatically; a flagged corroborator is reported for a human to look at, not acted on. Requires 'cache_dir' - with 'cache_dir = NULL' nothing is screened (zero extra NCBI calls) and 'corroborator_flagged' is 'NA' for every row, regardless of this parameter's value. 'FALSE' also skips this entirely (matching pre-2026-09-05 behavior). verbose: Logical (default 'TRUE'). |
| verbose | no | TRUE |  |

**Value:** A data frame with one row per removal candidate: 'accession', 'listed_taxon', 'action_production'/'action_audit', 'anywhere_production'/'anywhere_audit', 'n_partners_production'/'n_partners_audit', 'n_hits_audit', 'still_saturated' (the audit itself hit 'audit_max_hits', so its own window is also truncated), 'spared' ('TRUE'/'FALSE', or 'NA' when the audit itself never completed - i.e. 'action_aud

## Quick Start {#quick-start}

``` r
library(TaxaMatch)

# 1. Read DADA2 output
seqs <- read_sequence_table("seqtab_nochim.rds")

# 2. Filter by length and abundance
filtered <- filter_sequences(seqs, min_length = 100, max_length = 300,
                             min_abundance = 10)

# 3. BLAST against NCBI
blast_hits <- blast_sequences(filtered, database = "nt",
                              barcode_term = "12S",
                              min_score = 80)

# 4. Standardize to canonical match object
match_df <- standardize_match_data(blast_hits)

# 5. Remove redundant higher-rank hypotheses
match_df <- filter_redundant_hypotheses(match_df)
# Result: one row per observation_id x taxon hypothesis, ready for TaxaLikely
```

