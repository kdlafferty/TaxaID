# CONTEXT: TaxaMatch

**Store and Standardize Biological Match Data**

Stores and standardizes raw match data produced by external tools that compare biological observations (eDNA sequences, images, acoustic recordings) against reference databases. Outputs a canonical match object (one row per sample x reference match, with standard column names) for input to TaxaLikely. Match data sources include DNA barcode programs (e.g. MiFish), image classifiers, and acoustic recognizers. Also screens reference accessions for taxonomic mislabeling via independent BLAST-based congruence checking before the reference set is used for likelihood model training. Score-to-likelihood conversion itself lives in TaxaLikely. Part of the TaxaID ecosystem.

Version 1.0.0. 30 exported function(s).

## Functions

### add_lowest_consistent_rank(match_obj, rank_system = NULL, observation_id_col = "observation_id", na_as_inconsistent = FALSE, majority_threshold = NULL)

Add lowest consistent rank to a match object

For each observation, finds the finest taxonomic rank that has a single unambiguous value across all candidate rows. When four barnacle candidates share the same order but differ in family, genus, and species, the observation receives 'lowest_consistent_rank = "order"'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_obj | yes |  | Data frame. Standardised match object containing at least observation_id_col and the rank columns named in rank_system. |
| rank_system | no | NULL | Character vector or NULL. Rank columns to check, ordered coarse-to-fine (e.g. c("order","family","genus","species")). Auto-detected when NULL by matching column names against TaxaTools::extended_ranks. |
| observation_id_col | no | "observation_id" | Character. Name of the observation identifier column (default "observation_id"). |
| na_as_inconsistent | no | FALSE | Logical. When TRUE, blank ("") and NA values count as a distinct category: a rank is flagged inconsistent when some candidates have no value and others do. Default FALSE: blanks and NAs are ignored and only non-blank values are compared. |
| majority_threshold | no | NULL | Numeric in (0, 1] or NULL (default). When supplied, switches to majority mode: a rank is treated as consistent if the single most-common non-blank value accounts for at least this fraction of all non-blank candidate values. A value of 0.8 requires 4 of 5 candidates to agree. Values \le 0.5 are technically valid but semantically unusual (the "minority" would qualify as the majority). |

**Value:** 'match_obj' with one new column in strict mode, or four new columns in majority mode: 'lowest_consistent_rank' Character. The finest rank for which the consistency criterion is satisfied. 'NA' when no rank passes. 'rank_majority_value' (_majority mode only_) Character. The majority value at 'lowest_consistent_rank' for the observation. 'NA' when 'lowest_consistent_rank' is 'NA'. 'rank_majority_fraction' (_majority mode only_) Numeric. Fraction of non-blank candidates that hold 'rank_majority_value'. 'NA' when 'lowest_consistent_rank' is 'NA'. 'is_rank_outlier' (_majority mode only_) Logical. 'TRUE' for rows whose value at 'lowest_consistent_rank' differs from 'rank_majority_value'. Rows with 'NA'/blank values at that rank are 'FALSE' (missing data, not a contradiction). All rows are 'FALSE' when 'lowest_consistent_rank' is 'NA'. All original columns of 'match_obj' are retained unchanged; only the columns above are added.

#### Details

Designed to run after standardize_match_data() and (optionally) convert_taxonomy_backbone(). The resulting column can be used to filter out observations that are only resolvable to a coarse rank, or as a diagnostic to guide manual review.

Strict mode (default, majority_threshold = NULL): a rank is consistent only when every non-blank candidate value is identical.

Majority mode (majority_threshold in (0, 1]): a rank is consistent when the single most-common non-blank value accounts for at least majority_threshold of all non-blank candidate values. This handles the common case where one reference-library accession carries a misassigned rank value that would otherwise collapse the observation to a coarser rank. Three additional columns are added (see Value).

Warning: removing rows flagged by is_rank_outlier changes the candidate set seen by evaluate_likelihoods(). Do so before the likelihood step, and inspect the flagged rows before discarding them.

Edge cases: An observation with a single candidate row is always fully consistent at every rank (nothing to disagree with), so lowest_consistent_rank resolves to the finest rank in rank_system regardless of how well-supported that single candidate actually is -- this can give a false sense of resolution for a genuinely weak match.

A rank column that is entirely blank/NA for an observation counts as trivially consistent (no disagreement is possible with zero non-blank values), which does not block finer ranks from being evaluated. If all candidates lack a family value but agree on genus, this function can report lowest_consistent_rank = "species" even though every family value is missing -- this is deliberate (missing data should not prevent resolving finer ranks that ARE populated), but it means a "consistent" result does not imply every coarser rank was actually checked against real data.

Internally, na_as_inconsistent = TRUE mode uses the sentinel string "__MISSING__" to make blanks/NAs count as their own category. If any real taxon name in your data literally equals "__MISSING__", it would be misinterpreted as a blank placeholder -- an extremely unlikely collision in practice.

### assign_spatial_group(sites, observation_ids, spatial_group_id, id_col = "observation_id")

Manually Assign a Spatial Group to a Set of Observations

Sets 'spatial_group_id' directly for a named set of observations - for a study where the grouping is already known from metadata, or to hand-correct a few observations after 'group_observations_by_bbox''s interactive step - without drawing boxes. Guards against the one way this could silently corrupt an existing group: if 'spatial_group_id' is already in use by an observation *not* named in this call, that would silently expand an unrelated group's membership the next time anyone counts by 'spatial_group_id'. This function stops instead, so the caller can either include that observation ...

| Param | Required | Default | Doc |
|---|---|---|---|
| sites | yes |  | Data frame with (at least) id_col, spatial_group_id, and spatial_group_N columns -- typically the output of build_site_table or group_observations_by_bbox. |
| observation_ids | yes |  | Character vector of id_col values to assign to spatial_group_id. Must all already exist in sites. |
| spatial_group_id | yes |  | Character. Single, non-empty group id to assign. Can be a new id or an existing one (to add members to an already-formed group); see Details for the collision guard. |
| id_col | no | "observation_id" | Character. Observation ID column name. Default "observation_id". |

**Value:** 'sites' with 'spatial_group_id' set to 'spatial_group_id' for the named observations, 'spatial_group_N' recomputed for that group so it stays in sync, and (when present) 'is_default_group' set to 'FALSE' for the named observations - they are no longer eligible to be captured by a future 'group_observations_by_bbox' call. All other rows are unaffected.

#### Details

Collision guard: before assigning, checks whether spatial_group_id is already used by any observation outside observation_ids. If so, stops with an error naming those observations -- silently pulling in an unintended extra member is worse than a hard stop, since nothing downstream would notice the mistake until a fetch or a prior update used the wrong local species pool. To genuinely merge groups, include every observation you want in the merged group in observation_ids.

### blast_sequences(seq_df, method = "remote", database = "nt", program = "blastn", megablast = FALSE, score_range = 8, max_hits = 20L, max_hits_per_taxon = NULL, min_score = 70, min_query_coverage = 80, barcode_term = NULL, min_subject_length = NULL, max_subject_length = NULL, max_target_seqs = 100L, batch_size = 20L, max_batch_bp = 100000L, num_threads = NULL, word_size = NULL, email = Sys.getenv("NCBI_EMAIL", unset = ""), ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), resolve_taxonomy = TRUE, resolve_location = FALSE, poll_max_wait = 1800, max_consecutive_batch_failures = 3L, verbose = TRUE)

BLAST Sequences Against NCBI or a Local Database

Searches query sequences against NCBI nucleotide (remote) or a local BLAST database, then filters hits using a score window approach: retain all hits within 'score_range' percent identity of each query's top hit, up to 'max_hits' per query.

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_df | yes |  | Data frame with at least asv_id and sequence columns (e.g., output of read_sequence_table or filter_sequences). |
| method | no | "remote" | Character: "remote" (default) to use the NCBI BLAST URL API, or "local" to use a local BLAST+ database via the rBLAST package. Local mode runs whichever blastn is first on PATH, and the client must be able to read the database's LMDB index: NCBI's current core_nt carries a version-1 index that BLAST+ 2.16 reads and 2.17 does not (the error names MDB_INVALID). Put the matching client first on PATH for the session; TaxaWizard::workflow_check() reports the version it finds, and blastdbcmd -db <db> -info is the direct test. A database assembled from volumes fetched on different dates passes every per-volume checksum and still returns wrong records for accession and taxid lookups, silently; before trusting a local database, confirm that blastdbcmd -info reports one build date across its volumes and that the alias sequence count matches NCBI's current build. |
| database | no | "nt" | For remote: NCBI database name (default "nt"). For local: path to a local BLAST database. |
| program | no | "blastn" | BLAST program. Default "blastn". |
| megablast | no | FALSE | Logical. Default FALSE. Both the NCBI BLAST URL API (remote) and the standalone blastn binary (local, via rBLAST) default an unqualified program = "blastn" search to MEGABLAST mode when this isn't set explicitly -- a fast, greedy algorithm tuned to find a highly-similar hit quickly, not to exhaustively return every equally-good one. Confirmed on real data: a query with five reference sequences from one species and five from a second, genuinely tied at 100% identity over the full alignment, returned only a single hit from one species and none from the other under the implicit (megablast) default -- silently dropping a real, exactly-tied congener before score_range filtering ever had a chance to keep it. Set TRUE for the greedy megablast behavior for speed on very large batches; FALSE (classic blastn) is slower but the only mode confirmed to return every near-identical reference, which is what score_range's own tie-detection depends on. |
| score_range | no | 8 | Numeric. Keep all hits within this many percent identity points of each query's top hit (default 8 -- see "Score window validation" below). For example, if the top hit is 99% identity, all hits at 91% or above are retained. Wider ranges capture more taxonomic alternatives; narrower ranges (e.g., 2) focus on the closest matches only but risk silently dropping the true species when a congener happens to score higher (see Details). |
| max_hits | no | 20L | Integer. Safety cap: maximum hits to retain per query after score window filtering (default 20L). Increase for queries expected to match many closely related species. |
| max_hits_per_taxon | no | NULL | Integer or NULL (default). When set, caps the number of hits retained per taxon before max_hits is applied. Without this, one heavily-resequenced species -- e.g. a genus with many independently deposited mitogenomes of the same well-studied species -- can consume the entire max_hits budget with redundant near-duplicate hits, silently crowding out a real, different congener that would otherwise have survived score_range filtering. Each taxon's own best-scoring hit is always kept, so this never changes which taxon has the top score. Set to e.g. 3L to keep at most 3 representative hits per species. Requires resolve_taxonomy = TRUE to have any effect on remote BLAST results. Remote BLAST's XML output never populates a real per-hit taxid (staxids is always NA there), so grouping would otherwise be a silent no-op -- every hit would land in its own singleton group. When both are set, taxonomy is resolved once, early (on the min_score/coverage/length survivors, before this cap and max_hits run) specifically so grouping can use the real resolved species/genus name; the normal end-of-pipeline taxonomy resolution step is skipped since it's already done. This does mean more NCBI taxonomy lookups than the resolve_taxonomy = TRUE default alone (resolved on the larger pre-max_hits set, not the smaller final one) -- a real cost, only incurred when max_hits_per_taxon is actually requested. With resolve_taxonomy = FALSE, this falls back to grouping by staxids (a no-op for remote results, same as before this parameter existed) -- local BLAST via rBLAST does supply real staxids directly from its own database's taxonomy mapping, so this fallback is only inert for the remote path. |
| min_score | no | 70 | Numeric. Discard hits below this percent identity (default 70). The 70% threshold is a conventional cross-genus floor for DNA barcoding; most true species-level matches exceed 95%. |
| min_query_coverage | no | 80 | Numeric. Discard hits where less than this percentage of the query sequence aligned (default 80). Standard BLAST quality filter; ensures hits span most of the barcode region. |
| barcode_term | no | NULL | Character. Barcode marker name for auto-detecting the expected amplicon length bounds (e.g., "12S", "COI"). Default NULL. |
| min_subject_length | no | NULL | Integer. Minimum length, in bp, of the aligned region against the reference (not the reference accession's own total sequence length -- see Details). Overrides barcode_term. Default NULL. |
| max_subject_length | no | NULL | Integer. Maximum length, in bp, of the aligned region against the reference. Overrides barcode_term. Default NULL. |
| max_target_seqs | no | 100L | Integer. Number of hits to request from BLAST before client-side filtering (default 100L). Should be generous (larger than max_hits) since NCBI's default is 500. Set higher (e.g., 500) for comprehensive searches; lower for speed. |
| batch_size | no | 20L | Integer. For remote BLAST, number of sequences per submission (default 20L). Larger batches reduce API overhead but risk timeout on NCBI's server. NCBI handles multi-FASTA queries. |
| max_batch_bp | no | 100000L | Numeric. Remote BLAST only. Default 100000L. Cumulative-length (bp) cap per submission batch, applied ALONGSIDE batch_size -- a batch closes when EITHER the count or the bp limit is reached, whichever comes first. A long query (e.g. one of several full mitogenomes sharing a batch with mostly short amplicons) consumes vastly more server CPU than its count-based "1 of batch_size" share suggests -- one expensive query can doom an otherwise-cheap batch to a CPU-budget rejection (.blast_server_rejected()), and losing that whole batch to max_consecutive_batch_failures's circuit breaker costs every query it was sharing with, not just the expensive one. A single query at or above half of max_batch_bp rides ALONE in its own batch (closing whatever batch was already accumulating first, if any) -- isolating it this way guarantees a doomed batch only ever costs that ONE query's own progress. Inf disables the bp cap entirely, so batches close on batch_size count alone. See .split_batches_by_length() for the implementation. Most calls at the default batch_size/typical amplicon lengths never approach 100000L bp per batch, so this is a no-op for ordinary data -- it only ever triggers for real long-sequence batches. |
| num_threads | no | NULL | Integer or NULL (default). Local BLAST only: passed to blastn -num_threads. NULL uses every core but one. Output is identical at any thread count; only wall time changes (about 10x on 14 cores against core_nt). Ignored for remote. |
| word_size | no | NULL | Integer or NULL (default). Local BLAST only: passed to blastn -word_size, the length of the exact match that seeds an alignment. NULL leaves the program's own default (11 for megablast = FALSE). A local search against a database the size of core_nt spends most of its time extending short random seeds; 16 cut that time about 6x on real 12S queries while returning the same best-hit identity for every query, with differences confined to queries whose best hit was below about 83% identity, where an exact 16 bp seed can be absent. Scoring and the classic-blastn tie behaviour described under megablast are unchanged. Ignored for remote. |
| email | no | Sys.getenv("NCBI_EMAIL", unset = "") | Character. Email address sent to NCBI (required by their usage policy for remote BLAST). Defaults to the NCBI_EMAIL environment variable (unset by default); a warning() is issued for remote BLAST when neither is available. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | Character. Optional NCBI API key for higher rate limits. Defaults to the NCBI_API_KEY environment variable (unset by default). |
| resolve_taxonomy | no | TRUE | Logical. If TRUE (default), resolve NCBI taxonomy IDs to full lineage (kingdom through species) and append taxonomy columns to the output. |
| resolve_location | no | FALSE | Logical. Default FALSE. If TRUE, fetch each unique hit accession's full GenBank record (a real, separate NCBI round trip -- not free) and append lat/lon/ country columns parsed from the record's source feature lat_lon/country qualifiers. NA where the record has no collection-location metadata. Independent of resolve_taxonomy -- taxonomy comes from the NCBI taxonomy database, location from the full nucleotide record; neither fetch gives you the other. |
| poll_max_wait | no | 1800 | Numeric. Remote BLAST only. Seconds to keep polling NCBI for a submitted batch's results before giving up on it (default 1800, i.e. 30 minutes). The default accommodates sustained per-batch queue waits exceeding 600s, observed in a real, large (1,183-accession) remote-BLAST run. A batch that still exceeds this window (even after the existing halved-batch-size retry), OR that NCBI reports Status=READY for but has actually aborted server-side for exceeding a CPU-time fair-use budget (see .blast_server_rejected()'s own documentation for the real captured case that found this -- a real, distinct failure mode from a poll timeout, since NCBI returns a genuine, successfully- retrieved XML document, just one recording a rejection instead of real search results), is recorded in attr(result, "failed_query_ids") -- the affected asv_ids, so a caller can tell "search never completed or was rejected" apart from "search completed and found nothing," which evaluate_reference_accessions() uses to avoid caching a failed batch's accessions as if they were a real verdict. Neither failure mode is fixable by raising this parameter alone -- a CPU-budget rejection means NCBI is actively throttling this IP address's remote-BLAST usage; the real remedy is fewer/smaller/less frequent real calls (or method = "local" for a large batch job), not a longer wait. |
| max_consecutive_batch_failures | no | 3L | Integer. Remote BLAST only. Default 3L. A circuit breaker, distinct from poll_max_wait -- that parameter bounds how long ONE batch is allowed to take; this bounds how many CONSECUTIVE batches are allowed to fail before concluding the problem is systemic (sustained NCBI rate-limiting or CPU-budget throttling), not one unlucky batch, and stopping rather than continuing to submit batches that are likely doomed too. Without this, a sustained throttling episode means every remaining batch still pays its own full poll_max_wait before giving up -- for a large run (e.g. 60 batches at the default batch_size), that is many hours of guaranteed-doomed work before the function ever returns. A .blast_server_rejected() rejection counts double toward this threshold (a real, unambiguous throttle signal from NCBI itself); a plain poll timeout or submission failure counts once (could just be one slow/large batch). The counter resets to 0 on any batch that completes normally (including a real zero-hit result). When tripped: no further batches are submitted, every not-yet-attempted batch's queries are added to failed_query_ids (see below) alongside whatever had already failed, and the halved-batch-size retry pass is skipped entirely (retrying under a confirmed-systemic throttle wastes real NCBI time on batches already judged doomed). Set to Inf to disable the circuit breaker and retry every batch unconditionally. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |

**Value:** A data frame with one row per query x hit, containing: observation_id Query identifier (from 'asv_id') accession Subject accession score Percent identity (0-100 scale), computed as 'round(100 * identity / align_len, 2)' from HSP fields (the standard NCBI definition). This is _alignment_ identity over the aligned region, not sequence identity over the full query length. For multi-HSP alignments only the highest-scoring HSP is used, which may under- or over-estimate true coverage for fragmented/chimeric reads. evalue E-value bitscore Bit score alignment_length Alignment length query_coverage Percent of query aligned subject_length Subject sequence length subject_start, subject_end Where within the subject/reference sequence this hit's alignment falls (1-based, BLAST tabular convention - 'subject_start > subject_end' on the minus strand; use 'pmin()'/'pmax()' for a directionless span). Distinct from 'subject_length' (the reference's TOTAL length): lets a downstream consumer tell whether two hits against the SAME long subject (e.g. a complete mitogenome) actually cover the same genomic region or two unrelated ones - see 'TaxaLikely::restore_suppressed_candidates(check_regional_overlap = TRUE)'. If 'resolve_taxonomy = TRUE', taxonomy columns ('kingdom', 'phylum', 'class', 'order', 'family', 'genus', 'species') are appended. If 'resolve_location = TRUE', 'lat', 'lon', and 'country' columns are appended. This output is ready for 'standardize_match_data'. An 'attr(out, "report_params")' list ('method', 'database', 'min_query_coverage' - the coverage floor, read by 'TaxaLikely::evaluate_likelihoods()' to check it against the model's 'min_pair_coverage' - 'min_score', 'n_samples') is also attached, consumed by 'report_match'. 'attr(out, "failed_query_ids")' (character vector, 'NULL' if none) - remote BLAST only: 'asv_id's whose search never completed (submission or poll failure, even after the automatic halved-batch-size retry) - distinct from a query that completed and genuinely found nothing, which simply has no rows in 'out' at all. Present regardless of which return path this function takes, including every early-return-on-empty-result branch. See 'poll_max_wait''s own documentation. 'attr(out, "circuit_breaker_tripped")' (logical, always present for remote BLAST, 'FALSE' for local) - 'TRUE' when 'max_consecutive_batch_failures' was reached and remaining batches were skipped rather than attempted. Every skipped query's 'asv_id' is included in 'failed_query_ids' either way, so a caller that only checks 'failed_query_ids' still behaves correctly (nothing is silently miscoded as "searched, found nothing") - this attribute is for a caller that wants to distinguish "sustained throttling, stop trying more of this list right now" from an isolated batch failure and react differently (e.g. 'evaluate_reference_accessions()' uses it to stop processing further chunks and surface an actionable message).

#### Details

##### Score window algorithm

Rather than a flat top-N cutoff, hits are filtered per query:

- All hits below min_score are removed

- Hits with query coverage below min_query_coverage are removed

- Hits whose aligned region falls outside the barcode length range are removed (see "Subject length filter" below)

- For each query, the top hit's percent identity is found

- All hits within score_range of the top hit are retained

- A max_hits safety cap is applied per query

This means a clear top match may return only 1-3 hits (the rest are too distant), while an ambiguous query retains all plausible candidates.

##### Subject length filter

This step checks the length of the aligned region (the BLAST length field), not the reference accession's own total sequence length. A reference embedded in a long mitogenome or partial-genome record can match the whole query amplicon at 100% identity and 100% coverage, and it should be retained; checking the subject's own length against a ~130-210bp MiFish window would discard it, leaving only references that happen to be deposited as short standalone barcodes. The filter exists to catch the "wrong genomic region of the same gene" case (TaxaLikely's documented "Paralabrax footgun"), and a poor, partial, non-amplicon overlap is already excluded by min_query_coverage before this step runs.

##### Score window validation

This filter decides which candidates ever reach TaxaLikely/TaxaAssign, and a true species dropped here cannot be recovered downstream. A narrow score_range (e.g. 2, adequate for a clear top hit at 98% identity or above) is not safe in a taxonomically dense genus, where real congeneric divergence can be tight.

A leave-one-out check (the score_window_leave_one_out.R diagnostic, TaxaID_dev repository) treated each reference sequence as a query against every other sequence in three real reference-vs-reference distance matrices and asked how often a congener outscores the sequence's own true species:

- Sebastes (54 species): 3/113 (2.7%) queries, each by 0.6 points, so none would be dropped even at score_range = 2.

- Chromis (26 species): 3/33 (9.1%) queries, by 4.7-7.1 points, so all three would be silently dropped at score_range = 2.

- A 6-genus PtConception 12S set: 1/11 (9.1%) queries, by 2.5 points, which would also be dropped at score_range = 2.

Pooled, 4 of 7 congener-outscoring events (57%) exceed a score_range = 2 window. The default (8) covers every gap observed (worst case 7.1 points), but it is not a guarantee that no dataset will exceed it. max_hits (default 20) bounds the candidate count however wide score_range is set, and a wider window preserves the "gap" feature (TaxaLikely::train_likelihood_model()'s key discriminator between H1/H2/H3); dropping the true congener here removes the signal the model needs to flag a genuinely ambiguous call instead of confidently returning the wrong species.

##### Remote BLAST

Uses the NCBI BLAST URL API with proper rate limiting (minimum 10 seconds between submissions). Sequences are submitted in batches of batch_size. The function polls for results with exponential backoff. An email is required by NCBI usage policy. Remote BLAST results can vary over time as the NCBI nt database is updated; for reproducibility, consider recording the query date (or a specific database version, retrievable via NCBI Entrez) alongside results used in scientific workflows.

max_target_seqs does not guarantee the best-scoring hits are returned first -- NCBI's BLAST truncates its internal hit list before scoring is complete (Shah et al. 2018, Bioinformatics), so a low value can cause the true top hit to be missed. The default (100L) is reasonable for most barcode-length queries; raise it for taxonomically dense searches.

##### Local BLAST

Requires BLAST+ installed on the system and the rBLAST package (Bioconductor). Point database to a local BLAST database path. Much faster for large numbers of queries.

### build_site_table(match_df, site_df = NULL, id_col = "observation_id")

Build a Unified Long-Format Site Table

Produces one standardized site table - 'observation_id', 'lat', 'lon', 'observed_on' - regardless of which data-type pathway produced 'match_df'. This closes a contract gap across the three pathways: 'score_image_inat''s output already carries per-observation 'lat'/'lng'/'observed_on', but 'standardize_match_data' (DNA/BLAST) and 'read_birdnet_output' (acoustic) carry neither - for those, site information must be supplied separately via 'site_df'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | A match-object data frame from any TaxaMatch ingest function (score_image_inat, read_birdnet_output, standardize_match_data, ...). |
| site_df | no | NULL | Data frame with (at minimum) id_col, lat, and lon columns, required when match_df has no embedded lat/lng. Optional observed_on column. May have more than one row per id_col value -- this is the correct shape for a sequence ASV genuinely detected at several real sample sites (the same observation_id legitimately gets one row per site); do not pre-collapse to one row per observation before calling. Ignored (with a warning) when match_df already carries embedded site info. |
| id_col | no | "observation_id" | Character. Observation ID column name, present in both match_df and site_df. Default "observation_id". |

**Value:** A tibble in long format: one row per '(observation_id, site)' pair actually present in 'match_df', with columns 'id_col', 'lat', 'lon', 'observed_on' ('NA' where unknown), 'spatial_group_id', 'spatial_group_N', and 'is_default_group'. 'spatial_group_id' defaults to '"spatial_group_<n>"', grouping rows that share an *exact* '(lat, lon)' pair (see Details), and 'spatial_group_N' to the count of rows sharing that default label - until 'group_observations_by_bbox' (or 'assign_spatial_group') updates them in place for whichever observations get grouped. 'is_default_group' is 'TRUE' for every row until one of those two functions reassigns it; this is the marker they use to know which rows are still eligible to be captured by a newly drawn box or manual assignment, so they never need to re-derive "is this still a default" from 'spatial_group_id''s contents. This guarantees every site table has valid, non-missing 'spatial_group_id'/'spatial_group_N'/'is_default_group' values from the moment it is built, even before any grouping step runs.

#### Details

Why site info can't just be joined in generically: the image pathway embeds site info directly in the match object (one value per image); the acoustic pathway's BirdNET-Analyzer CSV output carries no site metadata at all (confirmed directly in read_birdnet_output()'s columns -- only detection window start/end times and the source filename); the DNA/BLAST pathway's observation_id is an ASV identifier that can be genuinely detected at multiple real sites within one sequencing run. site_df is therefore required (not derived) for the acoustic and DNA/BLAST pathways -- callers must build it from whatever recording-filename or sample-metadata convention their own study uses.

Why the default spatial_group_id is location-based, not observation-based: spatial_group_id is meant to answer "do these coordinates belong to the same neighborhood," a property of location, not of which observation happens to own a row. Defaulting it to observation_id instead would mean a genuine multi-site observation's own several sites always default to one shared group purely because they share an observation -- regardless of whether those sites are actually near each other -- while two genuinely co-located observations would never be grouped by default at all, contradicting this ecosystem's own stated design principle that clustering should be a geometric property of coordinates. The exact-match default handles both: two of one observation's own sites at different real coordinates now default to different groups (as they should), and two different observations sharing the exact same coordinate (typically because both were joined from the same site-metadata row -- e.g. join_event_site_metadata's pattern) now default to the same group (also as they should) -- group_observations_by_bbox's interactive step remains available as a refinement/override on top of this more sensible default, not the only mechanism that ever creates a shared group.

Why exact match, not grid-snapping/binning to a fixed resolution: a grid-snapping design (rounding coordinates to a fixed bin size) was tried first and rejected after live testing against this ecosystem's own bundled example data. A 0.1-degree bin collapsed four genuinely distinct observations (a real sample coordinate and a fallback/placeholder coordinate that happened to sit within ~11km of each other) into one default group -- reintroducing the exact "swept into an unrelated cluster" ambiguity this whole redesign exists to avoid. Choosing a "correct" bin size is not well-posed in general: it depends on how close together a given study's real sites happen to be, which this function has no way to know in advance. In this ecosystem's actual data flow, two coordinates that are supposed to represent the same site come from the same site-metadata lookup row (exactly equal), not from independent noisy GPS reads of the same physical spot (nearly, but not exactly, equal) -- so exact match is both simpler and the semantically correct comparison here, with no tuning parameter and no equivalent failure mode.

### check_marker_mismatch(accessions, expected_marker, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), verbose = TRUE)

Cross-Check a Reference Accession's Own Annotated Gene/Product Against an Expected Marker

Before investigating a flagged accession as a possible SPECIES mislabel (see 'investigate_flagged_accession()'), this does a single cheap GBSeq XML fetch and checks the record's own /gene or /product feature-table qualifier against the marker an evaluation was scoped to (e.g. does a "12S"-scoped audit's flagged record actually say /product="16S ribosomal RNA"?). No BLAST, no alignment - much cheaper than 'investigate_flagged_accession()''s deep dive, and meant to route a flagged accession to a completely different, simpler resolution path (correct the marker label, or exclude the ...

| Param | Required | Default | Doc |
|---|---|---|---|
| accessions | yes |  | Character vector of accessions to check. |
| expected_marker | yes |  | Character scalar (e.g. "12S", "16S", "COI") -- the marker/barcode the evaluation this accession was flagged under was scoped to. Matched case-insensitively against a small internal lookup of common marker-name synonyms as they actually appear in real GenBank /gene//product qualifiers (e.g. "12S" also matches "s-rRNA"/"small subunit ribosomal RNA"); an unlisted marker falls back to a literal, case-insensitive substring match on expected_marker itself. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | As in evaluate_reference_accessions(). |
| verbose | no | TRUE | As in evaluate_reference_accessions(). |

**Value:** A data frame, one row per unique input accession: 'accession' As supplied. 'expected_marker' As supplied. 'annotated_genes' Semicolon-joined, deduplicated /gene qualifier values found anywhere in the record's feature table. 'NA' if none were found (may still have /product annotation). 'annotated_products' Same, for /product. 'marker_match' 'TRUE' if ANY annotated /gene or /product text matches 'expected_marker''s resolved pattern; 'FALSE' if the record has real gene/CDS/rRNA/misc_feature annotation but none of it matches; 'NA' if the record has NO such annotation to judge at all - a distinct, honest outcome, not evidence of mismatch.

#### Why this exists

Directly grounded in a real, confirmed case from this ecosystem: AY850362 (a real GreatLakes 12S reference-database audit accession) is a genuine 16S-vs-12S MARKER mislabel, not a species mislabel. An earlier hypothesis -- that a disagreement resolved only at a coarse taxonomic rank (family/order/phylum) signals a marker/gene mislabel, while a disagreement at genus/species signals a real species mislabel -- was tested directly against MZ605481 (a real confirmed SPECIES mislabel) and refuted: MZ605481's own disagreement is also recorded at a coarse rank (order), yet is a real species mislabel, not a marker mislabel. What actually distinguishes the two is each record's own annotated gene/product metadata, not its taxonomic rank of disagreement -- this function checks that directly instead.

### convert_taxonomy_backbone(match_df, target_backbone_id, source_backbone_id = NULL, rank_system = c("order", "family", "genus", "species"), taxon_col = "taxon_name", update_taxon_name = TRUE, original_col = "taxon_name_original", backbone_col = "taxonomy_backbone", collision_col = "taxonomy_collision", verify_fn = TaxaTools::verify_taxon_names, verbose = TRUE)

Convert Match Object Taxonomy to a Target Backbone

Looks up each unique taxon name in 'match_df[[taxon_col]]' against a target taxonomic backbone (e.g. GBIF, NCBI), then replaces rank columns with the target backbone's hierarchy wherever the target provides a non-NA value (_per-column fallback_: ranks the target omits are left unchanged).

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | A data frame containing a taxon name column and rank columns. |
| target_backbone_id | yes |  | Integer. The target backbone identifier. Standard IDs: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS, 11 = GBIF. See https://verifier.globalnames.org/ for the full list. |
| source_backbone_id | no | NULL | Integer or NULL. The backbone that produced match_df's current hierarchy. Used only to label the taxonomy_collision column for rows not found in the target backbone. When NULL (default), not-found rows are labelled "original". |
| rank_system | no | c("order", "family", "genus", "species") | Character vector of rank column names to compare and potentially update, listed broadest to finest (e.g. c("order", "family", "genus", "species")). Columns absent from match_df are silently skipped. |
| taxon_col | no | "taxon_name" | Character. Name of the column containing the taxon name used as the lookup key (default "taxon_name"). |
| update_taxon_name | no | TRUE | Logical. When TRUE (default), match_df[[taxon_col]] is updated to the target backbone's accepted name (authority strings stripped via TaxaTools::clean_taxon_names()). The original value is preserved in match_df[[original_col]]. |
| original_col | no | "taxon_name_original" | Character. Name of the column to receive the original taxon name when update_taxon_name = TRUE (default "taxon_name_original"). Created if absent; unchanged if already present. |
| backbone_col | no | "taxonomy_backbone" | Character. Name of the column recording which backbone each row's hierarchy came from (default "taxonomy_backbone"). Created if absent. |
| collision_col | no | "taxonomy_collision" | Character. Name of the column recording the per-row conversion outcome (default "taxonomy_collision"). Created if absent. |
| verify_fn | no | TaxaTools::verify_taxon_names | Function. The name verification function to call. Must accept a character vector as its first argument and a backbone_id argument; must return a data frame with columns user_supplied_name, matched_name, classification_path, classification_ranks, and verified (logical: TRUE when the name resolved in the target backbone, FALSE/NA otherwise). An optional matched_rank column (the rank matched_name actually resolved at) enables the rank correction described below; a verify_fn without it is still fully supported, just without that correction. Default: TaxaTools::verify_taxon_names. Override for offline testing via dependency injection. The call is wrapped in tryCatch(); a failure (e.g. network unavailable, API rate-limited) raises a clear error naming the likely cause rather than propagating whatever uninformative error the API layer produced. |
| verbose | no | TRUE | Logical. Print the backbone column mapping summary message at the end. Default TRUE. warning()s for inconsistent taxonomy are always issued regardless of this setting. |

**Value:** 'match_df' with rank columns potentially updated, plus 'backbone_col', 'collision_col', and (when 'update_taxon_name = TRUE') 'original_col' columns added - 'backbone_col'/'collision_col' are created if absent and left unchanged (not overwritten) if already present, which matters for iterative/multi-pass pipeline use. The attribute 'backbone_cols' is set: a named list mapping '"backbone_N_cols"' to the rank column names that were subject to conversion, e.g. 'list(backbone_11_cols = c("order", "family"), backbone_4_cols = c("kingdom", "phylum"))'. Because R uses copy-on-modify semantics, the caller's original 'match_df' object is untouched; the return value must be (re)assigned.

#### Details

A taxonomy_collision column records what happened for each row:

- "consistent": Taxon found in target backbone; all supplied rank columns agree with the original.

- "backbone_N[col1,col2]": Taxon found; listed columns were changed to target backbone N values.

- "backbone_N" or "original": Taxon not found in target backbone; hierarchy unchanged. Label is "backbone_N" when source_backbone_id is supplied, otherwise "original".

A taxonomy_backbone column records which backbone the row's hierarchy was drawn from ("backbone_N" for found rows, source label for not-found rows).

#### Rank correction on fallback

When a row's own taxon_name_rank has no matching target-backbone value at that rank (e.g. a row claims "species" but the target only resolved the name to genus), match_df[[taxon_col]] falls back to the coarser resolved name and taxon_name_rank is corrected to match, using verify_fn's matched_rank column when present (silently skipped when verify_fn's return value lacks that column, e.g. a custom function injected for offline testing). For example, an informally-named NCBI reference ("Inu sp. 1 sensu Shibukawa et al., 2020.") resolves against GBIF to the genus Luciogobius (GBIF treats "Inu" as a synonym; NCBI does not) with no species-level entry to fill. Demoting taxon_name without correcting taxon_name_rank would leave a downstream slash-name builder treating the bare genus as a complete binomial and manufacturing a pseudo-binomial ("Inu Inu"). This is backbone-general, not GBIF-specific; see TaxaTools::verify_taxon_names()'s @section Synonym resolution and rank correctness.

Finer rank columns are also cleared on the same rows (e.g. species set to NA when the row is demoted to genus), not just taxon_name/taxon_name_rank. The per-column fallback (above) keeps each rank column's own cleaned original value when the target has no replacement, which would otherwise leave a stale value (species = "Inu") after taxon_name/taxon_name_rank were demoted. Code that re-derives a name from rank columns afterwards (e.g. a second TaxaTools::create_taxon_names() call) would see species still populated, apply "most specific non-NA rank wins", and silently undo the correction.

#### Rank correction on a genus-collapsing name, any source

The matched_rank-driven correction above fires only when the target backbone's reported rank disagrees with the row's claimed rank. A second, independent mechanism corrects taxon_name_rank whenever the value that ended up in taxon_name was produced by TaxaTools::clean_taxon_names() COLLAPSING a real second token to genus-only, whichever of three sources produced it: a not-found row's fallback cleaning; a found row's matched_name_clean fallback when its own rank had no target value; or a found row's own target_<rank> value at its claimed rank. It covers two cases: (1) an open-nomenclature, specimen-voucher-tagged label (e.g. "Ictalurus cf. pricei USON-01120-1") that never resolves in the target backbone (found_mask = FALSE); and (2) an NCBI taxonomy node for an informally named specimen (e.g. "Ictalurus sp. UM 105-1789", ranked "species" by NCBI), where found_mask = TRUE and matched_rank is genuinely "species" (so the matched_rank-driven correction correctly does nothing) but the species-rank value is the informal label, which collapses to genus-only when cleaned. No rank-mismatch correction can catch case (2); only the collapse signal reveals it. Without this correction, taxon_name_rank would stay at whatever rank the row claimed before conversion, labeling a bare genus as species-level.

The correction tracks the actual collapse event (via collapsed_to_genus) rather than re-deriving it from the final value's shape (e.g. via TaxaTools::is_plausible_binomial()), whose binomial regex requires a literal space after the genus token and would wrongly demote every hyphenated-genus species row (e.g. Pseudo-nitzschia). It requires "genus" to be present in rank_system, and is a no-op otherwise or when the input lacks the collapsed_to_genus attribute (e.g. from a clean_taxon_names()-alike that does not set it). Rank columns finer than the demoted rank are cleared, as in the matched_rank-driven correction.

An R attribute backbone_cols is set on the returned data frame recording which rank columns were subject to backbone conversion. A summary message is also printed.

#### Not-found rows are cleaned too

When a taxon is not found in the target backbone, its original rank columns and taxon_col value are still run through TaxaTools::clean_taxon_names() before being used as the output value. Without this, an exotic name that failed to resolve (e.g. a compound hybrid-formula name from a raw reference-database label, "((Citrus unshiu x Citrus sinensis) x Citrus reticulata) x Citrus reticulata") would pass through unmodified. This does NOT change which names are sent to verify_fn or which rows count as "found", only the fallback value's formatting.

### corroborate_references_locally(seq_matrix, reference_meta, min_overlap = 0.8, min_pident = 0.99, submission_window = 5L)

Corroborate Reference Labels From the Local Reference Set, Without BLAST

For each reference accession, asks whether an INDEPENDENT conspecific in the caller's own reference set (the one 'TaxaLikely::build_sequence_matrix()' was built from) matches it at high identity over most of the amplicon. A reference so corroborated does not need the BLAST screen ('evaluate_reference_accessions()') to confirm its label - and if the BLAST screen nevertheless says '"remove"', the local evidence vetoes that ('score_reference_labels()'). Zero NCBI cost.

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_matrix | yes |  | Data frame. TaxaLikely::build_sequence_matrix() output: id_x, id_y, p_match (0-1), coverage (0-1), species.x, species.y. Either a full pairwise table or one triangle -- pairs are symmetrised internally. |
| reference_meta | yes |  | Data frame. One row per reference: composite_id (or accession) and, optionally, create_date (a Date, or a string in "%Y/%m/%d" or "%Y-%m-%d" form) and species. The TaxaLikely::fetch_ncbi_reference_sequences() reference_df is exactly this. Without create_date, independence falls back to the accession-number heuristic alone. |
| min_overlap | no | 0.8 | Numeric in (0, 1] (default 0.8). Minimum coverage for a pair to count at all. |
| min_pident | no | 0.99 | Numeric in (0, 1] (default 0.99). Minimum identity of the best independent conspecific for local_tier = "corroborated". |
| submission_window | no | 5L | Integer (default 5L). As in evaluate_reference_accessions(); pass the same value used there. |

**Value:** A data frame, one row per accession (version suffix stripped) in the union of 'reference_meta' and 'seq_matrix': 'accession' Version-stripped id. 'species' From 'reference_meta$species' when present, else the accession's 'species.x' in 'seq_matrix'. 'n_conspecific' Distinct conspecific partners at 'coverage >= min_overlap', any batch. 'n_independent_conspecific' Of those, from a different submission batch. 'best_independent_pident' Highest 'p_match' (0-1) among the independent conspecifics; 'NA' if none. 'best_independent_partner' The partner supplying it (ties broken by id, so the result is deterministic). 'local_tier' '"singleton"' (no conspecific at sufficient overlap), '"same_batch_only"' (conspecifics, none independent), '"disagree"' (independent conspecifics, none at 'min_pident'), or '"corroborated"'. 'attr(result, "local_corroboration_params")' records 'min_overlap', 'min_pident' and 'submission_window'.

#### What "independent" means

Exactly what it means in evaluate_reference_accessions(): two accessions are the same submission batch if their create_dates are within submission_window days OR their accession numbers are within submission_window under the same prefix. The same internal helpers (.build_submission_batch_lookup() / .same_submission_batch()) are used, so "independent" means one thing in both places. A conspecific from the same batch is counted in n_conspecific but never corroborates -- the motivating true mislabel MN883227 (Fundulus luciae, actually a Pacific Fundulus) has a same-day sibling MN883226 at 100% that must not rescue it.

#### Why the overlap filter is not optional

p_match from build_sequence_matrix() is identity over the ALIGNED region; coverage is how much of the shorter sequence that region spans. KM057967 (Jordania zonope) looked corroborated by LC126244 at "100%" -- over a 5.6% overlap, about 40 bp of a different 12S region. Pairs with coverage < min_overlap (or NA coverage) are excluded before anything is counted, so Jordania is correctly a "singleton".

#### Where 0.99 comes from

min_pident must sit INSIDE the marker's intraspecific range. The motivating true mislabel MN883227 is corroborated locally by five independent conspecifics at 0.9814 -- 98% between "conspecifics" is what a sister-species swap looks like at MiFish-U, so 0.98 would veto/skip it and 0.99 keeps it screened. Re-deriving this from the trained H1 within-species distribution is a recorded later refinement, not built.

### evaluate_reference_accessions(accessions, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), insufficient_evidence_ttl_days = 180, incongruent_ttl_days = 30, top_n = 5L, min_congruent_rank = "family", hierarchy_incongruent_threshold = 0.5, min_independent_partners = 3L, submission_window = 5L, method = c("remote", "local"), database = "nt", score_range = 8, min_score = 70, max_hits = 20L, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), poll_max_wait = 1800, barcode_term = NULL, query_span = c("amplicon", "primer_inclusive"), chunk_size = NULL, max_consecutive_batch_failures = 3L, max_query_len = NULL, max_batch_bp = 100000L, prioritize_uncached = TRUE, retry_insufficient = TRUE, local_corroboration = NULL, skip_locally_corroborated = TRUE, num_threads = NULL, word_size = NULL, verbose = TRUE)

Evaluate Reference-Accession Quality via Unrestricted BLAST Comparison

For each accession, BLASTs its own sequence against a broad, *unrestricted* database (not scope-limited to any caller-chosen taxon list), applies the same-submission-batch independence filter, and computes a Jeffreys-smoothed taxonomic-hierarchy congruence verdict - the same congruence math 'TaxaLikely::audit_reference_database()'/'classify_reference_accessions()' computed from a narrow, taxon-list-scoped DECIPHER alignment (see that archived function's own roxygen for its full design), here fed from real, broad BLAST hits instead.

| Param | Required | Default | Doc |
|---|---|---|---|
| accessions | yes |  | Character vector of NCBI accessions to evaluate. Deduplicated internally. |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | Character or NULL. Default tools::R_user_dir("TaxaMatch", "cache"). Set NULL to disable caching entirely (every call re-evaluates every accession). |
| insufficient_evidence_ttl_days | no | 180 | Numeric (default 180). See Caching above. |
| incongruent_ttl_days | no | 30 | Numeric (default 30). Days after which an "incongruent" cached verdict is re-evaluated. Inf caches it indefinitely. Much shorter than insufficient_evidence_ttl_days on purpose, for two compounding reasons: "incongruent" is the only verdict that causes a reference to be REMOVED, and the thing that goes stale underneath it -- NCBI's nt snapshot -- is rebuilt on the order of days to weeks, not months. It is also ~1% of a real accession population (12 of 995 on the PtConception screen), so this is simultaneously the most valuable and the cheapest recheck available. See @section Why "incongruent" carries a TTL. |
| top_n | no | 5L | Integer (default 5L). Max independent BLAST hits ranked per accession for the congruence verdict. |
| min_congruent_rank | no | "family" | Character (default "family"). Passed to the shared congruence math -- see TaxaLikely::audit_reference_database()'s own roxygen for why "family", not a coarser rank, is this ecosystem's default. |
| hierarchy_incongruent_threshold | no | 0.5 | Numeric (default 0.5). An accession's smoothed frac_independent_below_min_congruent_rank at or above this value reads "incongruent". |
| min_independent_partners | no | 3L | Integer (default 3L). Fewer independent top matches than this reads "insufficient_independent_evidence" regardless of the fraction -- mirrors TaxaLikely::repair_thin_evidence()'s identical floor. |
| submission_window | no | 5L | Integer (default 5L). Days (or accession-number proximity) within which two accessions are treated as the same submission batch, and therefore non-independent evidence of each other. |
| method | no | c("remote", "local") | Passed through to blast_sequences() -- see that function's own documentation. Note that method = "local" moves only the BLAST search to the local database; the query records are still fetched from NCBI, so the screen is not offline in either mode. |
| database | no | "nt" | Passed through to blast_sequences() -- see that function's own documentation. Note that method = "local" moves only the BLAST search to the local database; the query records are still fetched from NCBI, so the screen is not offline in either mode. |
| score_range | no | 8 | Passed through to blast_sequences() -- see that function's own documentation. Note that method = "local" moves only the BLAST search to the local database; the query records are still fetched from NCBI, so the screen is not offline in either mode. |
| min_score | no | 70 | Passed through to blast_sequences() -- see that function's own documentation. Note that method = "local" moves only the BLAST search to the local database; the query records are still fetched from NCBI, so the screen is not offline in either mode. |
| max_hits | no | 20L | Passed through to blast_sequences() -- see that function's own documentation. Note that method = "local" moves only the BLAST search to the local database; the query records are still fetched from NCBI, so the screen is not offline in either mode. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | Character or NULL. Optional NCBI API key for higher rate limits (also forwarded to blast_sequences()). |
| poll_max_wait | no | 1800 | Numeric (default 1800, i.e. 30 minutes). Forwarded to blast_sequences(poll_max_wait =) -- how long to keep polling NCBI for one BLAST batch's results before giving up on it. An accession whose batch times out (even after blast_sequences()'s own automatic halved-batch-size retry) is treated the same as one NCBI has no record for at all -- excluded from this call's cache write and reported via $unresolved-style warning, NOT scored as "insufficient_independent_evidence" -- a real silent-miscache risk confirmed on a real, large (1,183- accession), multi-hour remote-BLAST run: sustained NCBI queue congestion can cause most batches after the first to time out, and every one of those accessions would otherwise be cached as a false "insufficient_independent_ evidence" verdict for up to insufficient_evidence_ttl_days (180 days by default) -- masking a real infrastructure failure as if it were a genuine evidentiary finding. |
| barcode_term | no | NULL | Character or NULL (default). When supplied, any query sequence exceeding the marker's expected length (via TaxaTools::resolve_barcode_lengths(barcode_term)) is trimmed to its amplicon region (via TaxaTools::resolve_barcode_primers(barcode_term) the same primer-matching algorithm as TaxaLikely::trim_to_amplicon(), duplicated here -- see .extract_amplicon_one_tm()'s own documentation) before being BLASTed, instead of submitting the full sequence. BLASTing a full-length over-length reference (e.g. a complete mitogenome, ~16.5kb) against a broad database is dramatically more CPU-expensive than BLASTing its short barcode region, and is confirmed to be the real cause of a live NCBI server-side CPU-budget rejection on a real, large run whose queries were often full mitogenomes (see poll_max_wait's own documentation for the real captured case) -- the accession's own species-identity signal lives in the short barcode region regardless, so trimming answers the identical question at a fraction of the cost. A sequence whose primer sites can't be found is next tried against the record's own annotated feature table (see @section Long-sequence robustness below), then, if still over-length, subject to the max_query_len hard cap -- never silently dropped or errored either way; at worst it is deferred as "not_evaluated_oversized", an explicit, labeled, TTL-retryable non-result. NULL (default) submits every sequence at full length. |
| query_span | no | c("amplicon", "primer_inclusive") | Character, "amplicon" (default) or "primer_inclusive". Which span of a barcode_term-trimmed query is submitted to BLAST: the primer-STRIPPED amplicon (the region between the two primer sites, ~169 bp for MiFish-U) or the primer-INCLUSIVE span (~217 bp). See @section Why the query is the primer-stripped amplicon. Verdict-affecting, so it is part of params_key. Ignored when barcode_term is NULL (nothing is trimmed), and moot for a marker with no registered primer pair in TaxaTools::barcode_primer_defaults (e.g. "18S", "ITS"): such queries are submitted AS DEPOSITED with a one-line message, never trimmed and never an error. Over-length records still go to the feature-table fallback. |
| chunk_size | no | NULL | Integer or NULL (default). Accessions needing real evaluation are processed this many at a time, with the persistent cache written after EACH chunk -- see @section Chunked evaluation and NCBI rate-limiting resilience below. NULL means 200L for method = "remote" (sized for NCBI's queue) and 1000L for method = "local", where each chunk is one blastn run that reads the whole database, so fewer, larger chunks spend less time reading it. Inf gives single-shot behavior (one chunk covering every accession, cache written only once at the very end). |
| max_consecutive_batch_failures | no | 3L | Numeric (default 3L). Forwarded to blast_sequences() -- see that function's own documentation for the full circuit-breaker mechanism (a .blast_server_rejected() rejection counts double toward this threshold; a plain poll timeout counts once). Inf disables it. |
| max_query_len | no | NULL | Numeric or NULL (default). The hard submission cap -- after BOTH barcode_term rescue strategies (primer trimming, then the feature-table-guided extraction fallback) have been tried, any query still longer than this is NOT submitted to BLAST at all. NULL resolves a default: 10x the marker's own amplicon_range upper bound (via TaxaTools::resolve_barcode_primers(barcode_term)) when barcode_term is supplied -- generous enough to never reject a real amplicon-length sequence, but small enough to exclude a full mitogenome or larger record -- or a flat 5000 when it is not (no marker-specific bound to derive one from). Inf disables the cap entirely (an unrescuable over-length query is always BLASTed at full length). See @section Long-sequence robustness below for the full mechanism and the new "not_evaluated_oversized" verdict this produces. |
| max_batch_bp | no | 100000L | Numeric (default 100000L). Forwarded to blast_sequences() -- see that function's own documentation for the length-aware BLAST batching this adds alongside the existing count-based batching. Inf disables it. |
| prioritize_uncached | no | TRUE | Logical (default TRUE). Orders needs_eval so accessions with NO existing cached verdict under the current call's parameters are evaluated before expired "insufficient_independent_evidence"/"not_evaluated_oversized" rows being retried past their TTL -- a budget-limited call (one that trips blast_sequences()'s own circuit breaker partway through) buys real NEW coverage first, rather than re-spending BLAST budget re-checking accessions that already have SOME cached answer. A pure ordering change within one call -- never changes which accessions end up evaluated, only in what order -- so, unlike every other new parameter here, this one changes existing default behavior deliberately: it is strictly better (or a no-op), never worse. |
| retry_insufficient | no | TRUE | Logical (default TRUE). FALSE skips retrying EXPIRED "insufficient_independent_evidence"/ "not_evaluated_oversized" cached rows entirely for this call -- they are served from cache as-is (their TTL notwithstanding) instead of being re-submitted to NCBI. Addresses a real documented complaint: by default, a call the caller expects to be purely cache-served (every accession already evaluated at least once) can still spend real BLAST budget re-checking every TTL-expired row, grinding against the same CPU-budget throttle this whole feature exists to survive. Set FALSE on a call where zero new NCBI cost is required this time. |
| local_corroboration | no | NULL | Data frame or NULL (default). Output of corroborate_references_locally() for the caller's own reference set. When supplied (and skip_locally_corroborated = TRUE), any accession whose local_tier is "corroborated" and that has no fresh cached verdict is NOT BLASTed: it is written to the cache as hierarchy_flag = "locally_corroborated" with n_independent_top_matches = n_independent_conspecific, best_agreeing_pident = 100 * best_independent_pident, congruent_evidence_exists_anywhere = TRUE, finest_common_rank = "species", and every other diagnostic NA. See @section Local corroboration. |
| skip_locally_corroborated | no | TRUE | Logical (default TRUE). FALSE sends locally-corroborated accessions to BLAST like any other, and also re-evaluates any row previously cached as "locally_corroborated" (that flag records a decision not to evaluate, not an evaluation). Not part of params_key. |
| num_threads | no | NULL | Integer or NULL (default). Local only: forwarded to blast_sequences(). NULL uses every core but one. Does not change any verdict, so it is not part of params_key. |
| word_size | no | NULL | Integer or NULL (default). Local only: forwarded to blast_sequences(). NULL means 16 for method = "local" and the program's own default for remote. It can change which hits BLAST returns, so it is part of params_key whenever it is set -- see @section Local search speed. |
| verbose | no | TRUE | Logical (default TRUE). Print progress messages. |

**Value:** A data frame, one row per unique input accession: 'accession' Exactly as supplied by the caller. 'listed_taxon' The accession's own labeled organism (from its real GenBank record). 'n_independent_top_matches' Independent BLAST hits actually used for the verdict (<= top_n). Also excludes any hit whose OWN listed species isn't itself resolved to species level - see @section Species-resolved comparison partners below. 'n_top_matches_available' All BLAST hits before the independence filter - diagnostic only. 'frac_independent_below_min_congruent_rank' Jeffreys-smoothed fraction of independent hits disagreeing at or above 'min_congruent_rank'. 'finest_common_rank' Finest rank at which the single best independent hit agrees with the listed taxon ('NA' if none), walking the full 'kingdom'->'species' ladder - see @section Coarse-rank diagnostic above. 'best_hit_pident' Percent identity (0-100) of the single best independent hit, regardless of whether it agrees or disagrees. 'best_agreeing_pident' Percent identity of the highest-identity independent hit that agrees at or above 'min_congruent_rank', among the 'top_n' slice used for the verdict itself. 'NA' if none agree. 'best_disagreeing_pident' Percent identity of the highest- identity independent hit that disagrees (coarser than 'min_congruent_rank'), among the 'top_n' slice. 'NA' if none disagree. See @section Identity diagnostics below for why this matters - a high value here is a much stronger mislabel signal than a low one, information the binary 'hierarchy_flag' alone cannot convey. 'best_disagreeing_taxon' The listed species of that same highest-identity disagreeing hit ('NA' if none disagree). Lets a reviewer - human or LLM - recognize e.g. a known hybrid-cross partner or an informal specimen code by name, not just by percent identity alone. 'congruent_evidence_exists_anywhere' Logical. Unlike 'hierarchy_flag' (computed only from the 'top_n' closest independent hits), this asks whether ANY independent hit anywhere in the full BLAST result (up to 'max_hits') agrees at or above 'min_congruent_rank'. 'FALSE' here is a stronger statement than an '"incongruent"' 'hierarchy_flag' alone - it means the listed rank has no representation at all among this accession's independent matches, not just none close enough to make the 'top_n' cut. 'congruent_evidence_best_pident' Percent identity of the best such anywhere-agreeing hit. 'NA' when 'congruent_evidence_exists_anywhere' is 'FALSE'. 'hierarchy_flag' '"congruent"', '"incongruent"', '"insufficient_independent_evidence"', '"not_evaluated_oversized"' (see @section Long-sequence robustness below; the query was never submitted to BLAST at all, so this is NOT evidence of anything, and downstream consumers ('flag_incongruent_references()', 'remove_incongruent_references()') never treat it as a flag), '"not_evaluated_wrong_marker"' (also never submitted, and also never a flag, but it names a CAUSE rather than a symptom: the record's own GBSeq feature table carries annotated features and none of them is the marker 'barcode_term' implies, so the accession does not belong in this screen's candidate set and no 'max_query_len' can rescue it), or '"locally_corroborated"' (skipped because an independent conspecific in the caller's own reference set already corroborates it; see @section Local corroboration. Treated like '"congruent"' everywhere downstream: never a flag, never removable, 'reference_action = "keep"'). 'NA' if the accession's own GenBank record could not be fetched (a 'warning()' is issued listing these; not cached, so a subsequent call retries them). 'local_corroborator_accession' The specific accession vouching for a '"locally_corroborated"' row - 'NA' for every other 'hierarchy_flag' value. '"locally_corroborated"' is cached indefinitely and exempt from 'refine_reference_verdicts()''s trust-weighted refinement (the MATCH itself, once observed, is permanent) - but the corroborator's own label is exactly as falsifiable as any other accession's, so this column exists to make that dependency visible and checkable, the same transparency 'verify_removal_candidates()' already gives its own corroborators. 'evaluated_at' When this verdict was computed ('NA' for a fetch failure). 'cache_hit' 'TRUE' if this row was read from 'cache_dir' rather than recomputed this call. 'taxonomy_resolution_source' '"direct"' (the accession's own NCBI taxonomy, the normal case), '"hybrid_maternal_proxy"' (a hybrid-labeled accession whose coarser-rank lineage was resolved from its maternal parent species instead - see @section Hybrid-labeled accessions below), '"hybrid_marker_not_maternal"' (hybrid-labeled with an unresolvable lineage, but 'barcode_term' is not a maternally inherited marker or is 'NULL', so no proxy), '"hybrid_unresolved"' (detected as hybrid-labeled but no usable parent species name could be extracted from the label, so the accession's own - structurally incomplete - NCBI lineage is used as-is), or 'NA' for a fetch failure. 'query_len_submitted' Integer. Base pairs actually sent to BLAST for this accession, after primer trimming and the annotation fallback. 'NA' for a row that was never submitted. 'query_trim_path' Which rescue produced the submitted sequence: '"as_deposited"', '"primer_match"' or '"feature_table"'. 'query_over_amplicon' Logical. 'TRUE' when the sequence submitted for this accession is longer than the marker's target amplicon, so its percent identities describe a WIDER REGION than a correctly trimmed row's and the two are not comparable. The trimming gate asks whether a deposit exceeds the marker's longest plausible length, not whether it exceeds the amplicon, and those differ for every registered marker with a primer pair - by 25 bp for MiFish-U and by 530 for COI-Leray, where a typical 658 bp Folmer deposit is never offered to the trimmer and whose feature table reads '"COI"' for the whole record, so neither rescue can shorten it. This column reports that footprint; it does not change what is submitted, because that would move every cached identity. A call with any such row also warns once, with the count and the median and longest submitted length. 'NA' for a row that was never submitted, and for a 'barcode_term' with no registered amplicon range. 'listed_taxon_is_species' Logical. 'FALSE' when 'listed_taxon' does not structurally look like a species-level binomial (via 'TaxaTools::is_plausible_binomial()' - e.g. a family name used in place of a genus with an informal specimen code, such as '"Serranidae sp. JL-2015"', a real GreatLakes case). A structurally different problem from both mislabeling ('hierarchy_flag') and hybrid-labeling ('taxonomy_resolution_source'): such a reference can't discriminate at species level regardless of whether it's internally self-consistent, so this can be 'FALSE' even when 'hierarchy_flag' reads '"congruent"'. 'NA' for a fetch failure (never 'FALSE' - a fetch failure means "not evaluated," not "evaluated and found non-species"). Also carries 'attr(result, "run_summary")' - a list ('n_total', 'n_from_cache', 'n_evaluated_this_call', 'n_skipped_locally_corroborated', 'n_pending', 'pct_complete', 'circuit_breaker_tripped', 'recommended_pause_minutes') summarizing what happened this call - see @section Chunked evaluation and NCBI rate-limiting resilience below.

#### Why this exists

A comparison population limited to whatever else was fetched under the caller's own taxa argument produces false positives (correctly-labeled accessions read "incongruent" because nothing else from their family happened to be in the list) and false negatives (a mislabeled accession's true contaminating identity is caught only if its genus is also on the list). BLASTing each accession against an unrestricted database removes the taxa-list dependency in both directions.

#### Scoping a large marker's screen

Per-accession remote BLAST does not scale to a large reference set under NCBI's throttle. Screening every accession of a large marker's reference set is NOT the recommended default; it is a deliberate, budgeted choice for when you want that coverage and can absorb the cost (chunk_size and max_consecutive_batch_failures make a full run survivable, not free).

The recommended default for a large marker scopes the screen to the two populations that drive real decisions, using existing tools:

- Accessions that actually drive a match. match_driving_accessions() returns only the accessions that are the max-scoring accession of their species for at least one real observation. Everything else can never change an assignment, whatever this function would say about it.

- Accessions the free local check can't already resolve. corroborate_references_locally() runs first, at no NCBI cost (it reuses the seq_matrix already built for training). Pass its output as local_corroboration with skip_locally_corroborated = TRUE and this function BLASTs only the accessions that check could not corroborate.

Every other accession is left unscreened by default; that is the documented scope, not an oversight.

#### Why "incongruent" carries a TTL

Caching a verdict indefinitely assumes it depends only on the accession's own sequence and label. This one also depends on what BLAST returns about the accession's NEIGHBOURHOOD, and that changes: an accession can read "incongruent" with no corroborating evidence and "congruent" on a later fetch, under an IDENTICAL params_key. BLAST is exactly reproducible at a fixed params_key, so this is not instability. NCBI's nt is a periodically rebuilt SNAPSHOT, not the live nuccore database, and a record public in Entrez need not be in the nt volume BLAST searches until a rebuild includes it. Both verdicts were correct for the database each was computed against, and the snapshot is what goes stale.

Without a TTL, the first (wrong) "incongruent" verdict would be served from cache forever, and it is the one verdict remove_incongruent_references() acts on destructively. nt rebuilds run on the order of days to weeks, so the default is 30 days, not the 180 of the "we do not know yet" flags: a longer TTL would keep serving a stale "incongruent" after the evidence that overturns it became searchable. The recheck costs about 1% of an accession population.

#### Coarse-rank diagnostic

finest_common_rank walks the FULL kingdom->species ladder (TaxaTools::standard_ranks), not just min_congruent_rank and finer. hierarchy_flag's classification threshold is unaffected: it fires at min_congruent_rank (default "family"). But finest_common_rank can report a real coarser match (e.g. "order") instead of NA as soon as "family" fails. This separates a SISTER family within the same order from an unrelated organism: both read "incongruent", but only the second is a cross-phylum mismatch. For example, a poorly resolved marker such as 18S combined with thin coverage of one family can produce an "incongruent" flag that is not necessarily a mislabel, and this column makes that visible without re-BLASTing by hand. Query-side taxonomy for every rank is resolved with the internal .resolve_taxonomy_by_acc() (the NCBI-taxonomy mechanism already used to classify BLAST hits), not TaxaTools::fill_higher_ranks() (GNVerifier-backed), so both sides of every comparison use the same authority.

#### Caching

Accessions are deduplicated (unique(accessions)) regardless of caching, so none is evaluated twice in one call. A persistent cross-run cache, keyed by accession alone (not by taxon, genus or project), means a project pays only for accessions that are new or previously out of scope. Staleness is handled per flag, following what each verdict CLAIMS:

- "congruent" -- cached indefinitely. It asserts that corroborating evidence WAS FOUND, and nothing a later BLAST returns can withdraw a match already observed.

- "incongruent" -- expires after incongruent_ttl_days (default 30). It asserts that corroborating evidence was NOT found, a statement about ABSENCE, which later evidence can overturn. See @section Why "incongruent" carries a TTL below.

- "insufficient_independent_evidence", "not_evaluated_oversized" and "not_evaluated_wrong_marker" -- expire after insufficient_evidence_ttl_days (default 180). All three mean "we do not know yet": new NCBI deposits (first), a later annotation or primer fix or a raised max_query_len (second), or a corrected upstream annotation or a different barcode_term, since the wrong-marker claim is relative to the marker THIS call asked for (third).

- "locally_corroborated" -- cached indefinitely, like "congruent": it asserts that corroborating evidence WAS found, in the caller's own reference set. It is re-evaluated only by a later call with skip_locally_corroborated = FALSE, which sends it to BLAST.

retry_insufficient = FALSE opts a single call out of retrying ANY expired row, serving the stale row instead (see that parameter). Setting incongruent_ttl_days = Inf caches "incongruent" indefinitely, like "congruent". TTLs are deliberately NOT part of params_key, so changing one does not invalidate a cache.

A cached row is recomputed if any parameter that affects the verdict (top_n, min_congruent_rank, submission_window, hierarchy_incongruent_threshold, min_independent_partners, score_range, min_score, max_hits, method, database, query_span) differs from the call that produced it. chunk_size, max_consecutive_batch_failures, max_query_len, max_batch_bp, prioritize_uncached, retry_insufficient, local_corroboration and skip_locally_corroborated are deliberately NOT in this list (see @section Long-sequence robustness). A row whose params_key does not match the current one, whether from an earlier internal cache version or different verdict-affecting arguments, is simply recomputed on the next call.

#### Local search speed

Against a database the size of core_nt, a local search spends its time per query, not per database scan, and almost all of it extending short random seed matches. Threads therefore help (on 12S queries, 200 queries took 184 s on one thread and 18 s on 14 threads with identical output), and word_size = 16 cut 90 s to 14 s for 1,000 queries. Compared with the default word size, 16 returned the same best-hit identity for every query and the same best-hit taxon for 99.9%, with differences confined to queries whose best hit was below about 83% identity, where the verdict already rests on distant relatives. Changing max_target_seqs alone moved about 2.5% of top-5 taxa in the same test, so this is within the noise BLAST's own settings carry.

#### Chunked evaluation and NCBI rate-limiting resilience

A large accession list is evaluated chunk_size accessions at a time, and the persistent cache is written after EACH chunk. Together with blast_sequences()'s circuit breaker (max_consecutive_batch_failures), a sustained NCBI rate-limiting or CPU-budget episode is detected and the function stops itself early instead of waiting out up to poll_max_wait for each doomed batch. When that happens, every accession evaluated in an earlier chunk is already cached; attr(result, "run_summary")$circuit_breaker_tripped is TRUE; and a message() reports the percentage resolved this call, the number still pending, and a recommended pause. Call the function again with the same accessions and cache_dir: cached accessions are read from the cache with no re-BLAST, so the resumed call pays only for what is outstanding.

#### Hybrid-labeled accessions

NCBI's taxonomy entry for a hybrid-cross-labeled organism (e.g. "Ctenopharyngodon idella x Megalobrama amblycephala") can be incomplete: the lineage may end at "unclassified Cyprinoidei" with no family, genus or species. Such an accession can never agree with an independent hit at family rank or finer, so the rank walk would read maximal disagreement, a false "incongruent" that is an artifact of the lineage, not a mislabel.

To avoid this, every rank coarser than species is taken from the accession's maternal parent species instead. mtDNA is maternally inherited, so a hybrid's barcode carries its maternal parent's lineage at kingdom through genus. The maternal parent is the first-listed parent in the formula (the GenBank convention lists the female parent first, though not always), cleaned with TaxaTools::clean_taxon_names() and resolved with TaxaTools::verify_taxon_names(backbone_id = 4L) (NCBI, the authority used everywhere else in this function). species.x is left as the accession's own hybrid label, never replaced by the proxy, because a hybrid is not the same species as its maternal parent.

The proxy requires a maternally inherited marker: barcode_term must name a mitochondrial (12S/MiFish/Teleo, 16S, COI, cytb, ND genes, control region) or chloroplast (rbcL, matK, trnL, psbA) marker. A nuclear marker (18S, ITS) carries both parents, and with barcode_term = NULL the genome cannot be established; such accessions are stamped "hybrid_marker_not_maternal" and keep their own lineage. Detection requires BOTH a standalone " x " token in listed_taxon AND an unresolvable family for the accession, so a non-hybrid taxon with an incomplete NCBI lineage (e.g. an undescribed species) is never given a maternal-parent substitution. A leading lowercase breeding or ploidy modifier (e.g. "androgenetic", "autodiploid", "autotetraploid") is stripped before clean_taxon_names() runs, since it changes the nuclear genome, not whose mitochondria the offspring carries. A label that still cannot be parsed into a usable proxy keeps the accession's own unresolved lineage, with taxonomy_resolution_source = "hybrid_unresolved".

#### Species-resolved comparison partners

An independent BLAST hit whose OWN listed species is not resolved to species level (e.g. "Serranidae sp. JL-2015", a family name used in place of a genus with an informal specimen code) is excluded from n_independent_top_matches and frac_independent_below_min_congruent_rank entirely, via require_species_resolved_partner = TRUE (the default; not a caller-facing parameter). Whether such a partner agrees or disagrees is not evidence either way, because its own identity is only loosely determined. A species whose only independent partner is of this kind therefore reads "insufficient_independent_evidence" rather than "incongruent". The check is TaxaTools::is_plausible_binomial(), the same one listed_taxon_is_species applies to the query side.

#### Identity diagnostics

hierarchy_flag and finest_common_rank alone cannot distinguish a genuine mislabel from "the listed rank has no well-covered independent relative in GenBank at this marker": both give the same rank-agreement output. Percent identity helps separate them. A DISAGREEING hit at ~99% identity is a real mislabel signal (the deposited sequence is nearly identical to something in a different family); a disagreeing hit at ~85-90% is unremarkable for a conserved marker such as 18S with poor resolving power at that rank. The best_*_pident columns give a caller that information to judge with; they are not a verdict, and no classification threshold in this function reads them.

#### Long-sequence robustness

barcode_term trimming shortens an over-length query when the primer sites can be found. A full mitogenome (or larger) record sent to remote BLAST at full length is far more CPU-expensive than a short amplicon and can cause sustained NCBI CPU-budget rejections, so five further mechanisms apply when the primer sites cannot be found:

- Feature-table-guided extraction fallback -- a query still over-length after primer trimming is checked against the record's OWN annotated GBSeq feature table for a feature matching the marker barcode_term implies, and that coordinate span (plus margin) is extracted instead. See .extract_feature_table_fallback() (R/trim_query_to_amplicon.R), which reuses check_marker_mismatch()'s fetch/matching internals (R/check_marker_mismatch.R).

- Hard submission cap -- max_query_len: a query still over-length after BOTH rescue strategies is never submitted. It gets a cached row, hierarchy_flag = "not_evaluated_oversized", with every diagnostic column NA: an explicit, labeled non-result, not a silent drop. TTL-retryable like "insufficient_independent_evidence" (see @section Caching), so a later annotation fix, primer update, or raised max_query_len can rescue it.

- Wrong marker, separated from wrong size -- when the feature-table fallback declined because the record HAS annotated features and none is this marker, the deferred row reads "not_evaluated_wrong_marker" instead. "oversized" implies a size problem that raising max_query_len could fix; for this class no length helps, because the accession does not belong in the candidate set. If you see many oversized rows, check what fraction are really this case.

- Length-aware BLAST batching -- max_batch_bp, forwarded to blast_sequences(): closes a submission batch on a cumulative bp cap as well as the count cap, and sends one very long query alone rather than letting it doom a batch of otherwise-cheap queries.

- Retry-priority ordering and a retry switch -- prioritize_uncached (default TRUE) and retry_insufficient (default TRUE; FALSE makes a call purely cache-served, spending no new NCBI budget on expired retries).

max_query_len, max_batch_bp, prioritize_uncached and retry_insufficient are deliberately excluded from params_key, like chunk_size and max_consecutive_batch_failures: they govern how and whether work is submitted this call, not what verdict an accession's evidence produces, so changing them never invalidates a cached "congruent" or "incongruent" row. Only query_span (see below) does.

#### Why the query is the primer-stripped amplicon

The screen runs blastn (megablast = FALSE, +2 match / -3 mismatch). With the primer-INCLUSIVE 217 bp MiFish-U query, a 169 bp perfect conspecific amplicon-only deposit scores 338 raw, while every full-length relative at 93.1% identity or more over the whole 217 bp scores 359 or more. NCBI's HITLIST_SIZE = 100 list then fills with mitogenome relatives and the short perfect conspecific never arrives. Separately, blast_sequences()'s default min_query_coverage = 80 would drop it anyway (169/217 = 77.9%). The consequence is a false "remove" ("no conspecific evidence anywhere in nt") for an accession that has a 100% identity conspecific amplicon-only deposit. With the primers stripped (169 bp) both barriers vanish and min_query_coverage needs no change. Because this changes what is submitted, it is verdict-affecting: query_span is in params_key, so a cached row written under a different query_span (or any other verdict-affecting argument) is re-BLASTed on the next call.

#### Local corroboration

If an ASV matches several references of the same species that agree with each other, there is no need to BLAST any of them. corroborate_references_locally() answers that from the workflow's own seq_matrix for free: a reference whose best INDEPENDENT conspecific (different submission batch, the screen's own rule) matches at min_pident or more over min_overlap or more of the amplicon is "corroborated". Passed here as local_corroboration, such accessions are skipped rather than BLASTed and cached as "locally_corroborated" with TTL Inf. score_reference_labels() uses the same table for provenance (corroboration_source) and to VETO a BLAST "remove" down to "inspect" when the local set corroborates the label. The overlap filter is not optional: a "100%" match over a few percent of the amplicon (e.g. ~40 bp of a different 12S region) is not corroboration.

### filter_redundant_hypotheses(match_df, rank_system = c("kingdom", "phylum", "class", "order", "family", "genus", "species"))

Filter Redundant Higher-Rank Hypotheses

Removes coarser-rank rows that are superseded by finer-rank rows within the same lineage and 'observation_id'. Redundancy is *lineage-local*: a genus-level row for _Gobius_ is dropped only if a _Gobius_ species row also exists for the same 'observation_id'. A genus row for a different lineage (e.g., _Acanthogobius_) is retained even when _Gobius_ species rows are present.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | A data frame with at minimum the columns observation_id, taxon_name_rank, and one column for each rank named in rank_system. Rows whose taxon_name_rank is not found in rank_system are retained unchanged and a warning is emitted listing the unrecognised values. Rows with NA taxon_name_rank are also silently retained (no warning) -- they cannot be compared against rank_system at all. Two species-level rows for different species sharing the same genus/family (e.g. Gobius paganellus and Gobius bucchichi) are both retained and neither's genus row is dropped -- this function only removes strictly redundant ancestor rows, not competing same-rank candidates (disambiguating those is TaxaLikely's job). |
| rank_system | no | c("kingdom", "phylum", "class", "order", "family", "genus", "species") | Character vector of taxonomic rank names in coarsest-to-finest order. Defaults to c("kingdom","phylum","class","order","family","genus","species"). Each name must match both an element of taxon_name_rank and a column name in match_df (case-sensitive after standardize_match_data() has lowercased everything) -- if match_df has not been through standardize_match_data(), rank column names may not match this default and no rows will be removed (a warning() is issued when none of rank_system matches a match_df column at all). |

**Value:** A data frame with the same columns as 'match_df' but with redundant higher-rank rows removed. Row order and all other attributes are preserved.

#### Details

Should be called after standardize_match_data() (or any step that populates taxon_name_rank) so that rank labels are already in the canonical lowercase form used by rank_system.

### filter_sequences(seq_df, barcode_term = NULL, min_length = NULL, max_length = NULL, min_abundance = 2L)

Filter Sequences by Length and Abundance

Removes sequences that fall outside acceptable length bounds or below a minimum abundance threshold. Length bounds can be set automatically from a barcode marker name or specified manually.

| Param | Required | Default | Doc |
|---|---|---|---|
| seq_df | yes |  | Data frame from read_sequence_table, or any data frame with sequence (or length) and abundance columns. |
| barcode_term | no | NULL | Character string identifying the barcode marker (e.g., "12S", "COI", "MiFish"). Used to auto-detect length bounds. Ignored if both min_length and max_length are specified. Default NULL. |
| min_length | no | NULL | Minimum sequence length in base pairs. Overrides barcode_term default. Default NULL. |
| max_length | no | NULL | Maximum sequence length in base pairs. Overrides barcode_term default. Default NULL. |
| min_abundance | no | 2L | Minimum total read count to retain a sequence. Sequences with fewer reads are removed. Default 2 (removes singletons). |

**Value:** A filtered data frame (same structure as input). A message reports how many sequences were removed and why. An 'attr(out, "report_params")' list ('min_length', 'max_length', 'min_abundance', 'n_retained') is also attached, mirroring 'blast_sequences()''s own 'report_params' attribute, so downstream reporting functions can incorporate the filtering parameters into automated methods text.

#### Details

Singletons (sequences observed only once across all samples) are commonly removed in eDNA workflows because they are enriched for PCR/sequencing errors. The default min_abundance = 2 removes these. When seq_df has no abundance column, abundance filtering is silently skipped with a message() (not a warning or error).

When barcode_term is supplied, length bounds are resolved from an internal lookup table covering common eDNA markers (12S, 16S, COI, ITS, etc.). These are intentionally broad ranges that exclude obvious non-target amplicons while retaining genuine length variation.

The length filter operates on seq_df$length if present, computing it from seq_df$sequence otherwise. If length was pre-computed by an upstream step from a different string (e.g. a provider's reported length that includes alignment gaps), the filter is applied to that value, not to nchar(sequence) -- verify the two agree when using a provider-supplied data frame directly (not one produced by read_sequence_table(), which always derives length from sequence itself).

### flag_incongruent_references(match_df, evaluation)

Annotate a Match Object with Reference-Accession Quality, Without Removing Anything

The RECOMMENDED default consumer of 'evaluate_reference_accessions()' - left-joins its evaluation columns onto 'match_df' by accession (version-suffix-stripped, same convention as 'remove_incongruent_references()') so 'hierarchy_flag' and the identity/ coverage diagnostics travel with the match object for review, without ever discarding a candidate taxon.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. A standardized match object (from standardize_match_data()) containing an accession column. |
| evaluation | yes |  | Data frame. Output of evaluate_reference_accessions(). |

**Value:** 'match_df' with 'hierarchy_flag', 'finest_common_rank', 'frac_independent_below_min_congruent_rank', 'n_independent_top_matches', 'n_top_matches_available', 'best_hit_pident', 'best_agreeing_pident', 'best_disagreeing_pident', 'congruent_evidence_exists_anywhere', and 'congruent_evidence_best_pident' joined on, plus 'label_confidence', 'label_identity_margin', 'reference_action' and 'listed_taxon_is_species' whenever 'evaluation' carries them (it always does when it came from 'evaluate_reference_accessions()' or 'score_reference_labels()'; an 'evaluation' read straight off a cache file created before these columns existed will not). A row whose accession was not found in 'evaluation' gets 'NA' in all of these (not evaluated yet, not evidence of anything). Row count and order are unchanged.

#### Why flag-by-default, not drop-by-default

A real case (Abylopsis eschscholtzii, KY594854/KX384617) shows why an unreviewed hard drop is the wrong default: hierarchy_flag = "incongruent" cannot currently distinguish a genuine mislabel from "correct label, but this marker has poor resolving power at this rank for this clade and GenBank coverage is thin" -- see evaluate_reference_accessions()'s own @section Identity diagnostics. Dropping the accession destroys the candidate taxon entirely and irreversibly on the strength of a verdict that can be wrong in exactly this ambiguous way. The same pattern recurs elsewhere in this ecosystem with unrelated mechanisms, for the identical reason -- TaxaLikely::apply_coverage_constraints(constraint_behavior) defaults to "relabel" rather than "zero" (a genus-completeness NCBI-query result treated as certain ground truth would permanently discard a correct hypothesis with no way for downstream evidence to recover it), and TaxaFetch::filter_gbif_quality() defaults to flag_institution rather than exclude_institution (real, correctly-labeled observations near a biodiversity institution would otherwise be auto-removed alongside real errors, since proximity to an institution -- like thin reference coverage for a correctly-labeled clade -- is not itself proof of error). Use this function by default; reach for remove_incongruent_references() deliberately, after review, not as the default pipeline step.

#### When evaluation carries more than one row per accession

evaluate_reference_accessions() keys its own cache on the literal (version-suffixed) accession string, so two rows of evaluation can share the same version-stripped accession -- e.g. "AB123.1" and "AB123.2", evaluated independently. No other function in this package picks a single row among same-accession duplicates (remove_incongruent_references() removes a match_df row if ANY of its accession's evaluation rows was flagged, never selects one; .local_corroboration_columns() keeps whichever row happens to sort first). In the absence of an established rule, this function keeps the row with the HIGHEST numeric version suffix (an accession with no version suffix sorts below any versioned one) before joining, so every match_df row is matched to at most one evaluation row and row count/order are preserved exactly as documented below.

### group_observations_by_bbox(sites, id_col = "observation_id", lat_col = "lat", lon_col = "lon", tile = "Esri.OceanBasemap")

Group Observations by User-Drawn Bounding Boxes

Plots all observations' site coordinates and lets the user draw one or more bounding-box polygons (via repeated calls to 'define_search_polygon') to define spatial groups. Observations whose coordinates fall within a drawn box share a 'spatial_group_id' and can use one pooled, community-level occurrence/reference fetch (the existing clustered pipeline design). Observations that never fall inside any drawn box - including every observation, if the user draws no box at all - are *not dropped*: they are left at their existing 'spatial_group_id' (by default, from 'build_site_table', a ...

| Param | Required | Default | Doc |
|---|---|---|---|
| sites | yes |  | Data frame with one row per observation, containing at least id_col, lat_col, and lon_col. Typically the output of build_site_table, which already carries spatial_group_id/spatial_group_N/is_default_group defaults -- this function updates those columns in place for whichever observations get captured by a drawn box, leaving everything else untouched. is_default_group (not the contents of spatial_group_id itself) is what this function checks to decide which rows are still eligible to be captured by a new box -- so it works the same way regardless of what build_site_table()'s default label happens to look like. If sites has no spatial_group_id/spatial_group_N columns at all (i.e. it did not come from build_site_table()), singleton defaults are initialized first, with a message. spatial_group_id/ spatial_group_N without is_default_group is not a recognized shape -- build_site_table always sets all three together -- and stops with an error naming the missing column. |
| id_col | no | "observation_id" | Character. Column identifying each observation. Default "observation_id". |
| lat_col | no | "lat" | Character. Latitude/longitude column names. Default "lat" / "lon". |
| lon_col | no | "lon" | Character. Latitude/longitude column names. Default "lat" / "lon". |
| tile | no | "Esri.OceanBasemap" | Character. Leaflet tile provider, passed to define_search_polygon. Default "Esri.OceanBasemap". |

**Value:** 'sites' with 'spatial_group_id'/'spatial_group_N'/ 'is_default_group' updated in place: observations captured by a drawn box (in draw order; an observation falling inside more than one box gets the *most recently drawn* one, with a warning - see Details) get '"spatial_group_1"', '"spatial_group_2"', ..., 'spatial_group_N' equal to that group's member count, and 'is_default_group = FALSE'. Observations already in a non-default (previously grouped, or manually assigned via 'assign_spatial_group') group are left untouched regardless of geometry. Everything else keeps its existing default. A message reports how many observations were left at their default group and why.

#### Details

Interaction model: each iteration re-centres define_search_polygon on the bounding box of the still-ungrouped observations (guaranteed to fully enclose them -- see .bbox_center_radius()) and overlays them as reference points. Draw a box around a cluster and click Done to record that group and continue to the next box; click Cancel (the title-bar X) when you are finished drawing boxes. This opens an end-of-loop review: a numbered list of drawn groups with their member counts, where you can enter a number to reopen that group's polygon for reshaping, "delete <n>" to remove it (releasing its members back to their default), or press Enter to finalize.

Run this as one isolated command in RStudio. The end-of-loop review step reads console input via readline(). If you select and run this call together with other lines (e.g. highlighting both grouped <- group_observations_by_bbox(sites) and a following print(grouped) and pressing Cmd/Ctrl+Enter once), RStudio queues the remaining line(s) as pending console input -- readline() will silently consume that queued text as its answer instead of waiting for you to type one, which can finalize early, misinterpret a queued blank line as "done", or otherwise produce a result that does not match what you actually drew. Run this call on its own, watch the console for the box-by-box progress messages and the final review prompt, answer it explicitly, and only then run any follow-up command.

Overlap rule: if an observation falls inside more than one drawn polygon, the most recently drawn polygon's group claims it -- a later box is more likely to be a deliberate correction/refinement of an earlier one covering the same area. A warning() lists every ambiguous observation_id.

Fetch-scope consequence (not performed by this function): multi-member spatial groups are intended to share one pooled bounding-box occurrence/reference fetch. Single-observation spatial groups are intended to be fetched per-observation, scoped to that observation's own candidate taxa, broadened taxonomically rather than spatially. TaxaAssign::update_prior_from_consensus() pools confirmation evidence within each spatial group only, so a single-observation group neither donates nor receives -- see its spatial_group_map and detections arguments.

### investigate_flagged_accession(accession, species = NULL, max_related = 30L, method = c("remote", "local"), database = "nt", score_range = 8, min_score = 70, max_hits = 20L, submission_window = 5L, min_coverage = 0.5, max_length_ratio = 3, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), inconclusive_ttl_days = 30, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), verbose = TRUE)

Deep-Dive Verification for a Single Flagged Reference Accession

For ONE accession 'evaluate_reference_accessions()' flagged (typically '"incongruent"'), runs two targeted, more expensive comparisons than that broad-scan function ever attempts - deliberately meant to run only on the small subset a caller has already decided is worth a closer look, not at production scale.

| Param | Required | Default | Doc |
|---|---|---|---|
| accession | yes |  | Character scalar. The flagged accession to investigate. |
| species | no | NULL | Character or NULL (default). The accession's own listed species -- if NULL, fetched from its real GenBank record. |
| max_related | no | 30L | Integer (default 30L). Caps how many conspecific/ disagreeing-taxon accessions are fetched and compared against, for each of the two comparisons -- a deliberate bound, not exhaustive reference-database compilation (see TaxaLikely::fetch_ncbi_reference_sequences() for that). |
| method | no | c("remote", "local") | Passed to BOTH the disagreeing-taxon re-BLAST AND the two .blast_against_comparison_set() comparisons (self-consistency, cross-taxon) -- see blast_sequences(). |
| database | no | "nt" | Passed to BOTH the disagreeing-taxon re-BLAST AND the two .blast_against_comparison_set() comparisons (self-consistency, cross-taxon) -- see blast_sequences(). |
| score_range | no | 8 | Passed only to the disagreeing-taxon re-BLAST -- see blast_sequences(). The two comparison-set BLAST calls use their own internal, deliberately permissive values (see .blast_against_comparison_set()), since they exist to honestly report every comparison-set accession's real identity/coverage, not to apply a score-window cutoff. |
| min_score | no | 70 | Passed only to the disagreeing-taxon re-BLAST -- see blast_sequences(). The two comparison-set BLAST calls use their own internal, deliberately permissive values (see .blast_against_comparison_set()), since they exist to honestly report every comparison-set accession's real identity/coverage, not to apply a score-window cutoff. |
| max_hits | no | 20L | Passed only to the disagreeing-taxon re-BLAST -- see blast_sequences(). The two comparison-set BLAST calls use their own internal, deliberately permissive values (see .blast_against_comparison_set()), since they exist to honestly report every comparison-set accession's real identity/coverage, not to apply a score-window cutoff. |
| submission_window | no | 5L | Integer (default 5L). Same-submission-batch independence-filter window, matching evaluate_reference_accessions()'s own default. |
| min_coverage | no | 0.5 | Numeric (default 0.5). Passed to .blast_against_comparison_set() -- see that function's own documentation. Comparisons below this floor are retained in the output (never silently dropped) but excluded from the printed headline mean/range. |
| max_length_ratio | no | 3 | Numeric (default 3). Passed to .search_species_accessions() -- REQUIRED for correctness, not an optional tuning knob (see that function's own @section Length-ratio pre-filter: a plain NCBI organism-name search can be dominated by whole-genome-assembly records for a species with a published reference genome, leaving almost no length-comparable candidates in the raw result at all). |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | Character or NULL. Default tools::R_user_dir("TaxaMatch", "cache"). Set NULL to disable caching entirely (every call re-investigates from scratch). See @section Caching above. |
| inconclusive_ttl_days | no | 30 | Numeric (default 30). See @section Caching above. |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | As in evaluate_reference_accessions(). |
| verbose | no | TRUE | As in evaluate_reference_accessions(). |

**Value:** A list: 'accession', 'listed_species' As given/discovered. 'conspecific_comparison' data.frame(accession, pident, coverage, meets_min_coverage, create_date) - one row per real conspecific accession BLAST actually returned a hit for. ALWAYS check 'coverage'/'meets_min_coverage' before trusting 'pident' - a high 'pident' at low coverage is not meaningful evidence of anything, see 'min_coverage' above. 'disagreeing_taxon' The species name of the top independent disagreeing BLAST hit, or 'NA' if none found. 'disagreeing_taxon_comparison' Same shape as 'conspecific_comparison', for 'disagreeing_taxon''s own other accessions. Also prints a narrative summary comparing the two, unless 'verbose = FALSE'.

#### Why this exists

The raw top BLAST hits for a flagged accession can be actively misleading. Hits at ~99.5% identity to an eel, a catfish and a parasitic isopod look like severe contamination, yet may all come from the SAME submission batch as the query. evaluate_reference_accessions()'s independence filter already excludes those, but the exclusion is invisible without re-fetching the raw GenBank records by hand. This function automates that verification, applying the SAME independence-filter logic (.build_submission_batch_lookup() and .same_submission_batch()).

#### The two comparisons

- Self-consistency: How well does the flagged accession match OTHER GenBank accessions of its own listed species (searched directly by species name, not discovered via blast_sequences()'s own score_range/max_hits window, which can miss real conspecifics just outside it)? High identity is reassuring; low identity is a much stronger warning than evaluate_reference_accessions() alone can report, since the accession does not resemble other deposits of its own claimed species.

- Cross-taxon consistency: How well does the flagged accession match other accessions of whichever taxon its top INDEPENDENT disagreeing BLAST hit belongs to (re-discovered with a live BLAST call, independence-filtered the same way)? High identity here paired with low self-consistency is the strongest evidence this function can produce for a genuine mislabel.

#### Why both comparisons run via BLAST, not pairwise alignment

A pairwise-alignment approach can come back inconclusive in BOTH directions. NCBI's [Organism]-based search returns records of ANY length, and most deposits for a species are full ~16kb mitogenomes, against which a ~173bp amplicon can only find a small, non-meaningful local-alignment fragment, so few or no candidates clear a 50% coverage floor. A direct blast_sequences() call already enforces min_query_coverage internally and returns coverage-safe independent hits. Both comparisons therefore reuse that mechanism (.blast_against_comparison_set(), internal) rather than a hand-rolled pwalign::pairwiseAlignment() loop.

#### Why a length-ratio pre-filter is required alongside the scoped BLAST search

Scoping the comparison-set search via NCBI's ENTREZ_QUERY mechanism (see .blast_against_comparison_set()'s @section Why the comparison-set search is scoped, not post-hoc filtered) is not enough on its own. For a species with a published reference genome, most candidates can be whole-chromosome shotgun-assembly records tens of millions of bp long, and the few short candidates may cover a different gene entirely; neither BLAST restriction can find a meaningful alignment against such candidates. The length-ratio candidate pre-filter is therefore a REQUIRED companion to the scoped BLAST search, not an alternative to it. It is implemented in .search_species_accessions() (reference_length and max_length_ratio), using NCBI's already-batched, free slen ESummary field to filter BEFORE fetching full sequence content, since fetching a 70-million-bp record's GBSeq_sequence silently fails and returns NA.

#### Caching

A persistent cross-call cache keyed on (accession, species override) mirrors evaluate_reference_accessions()'s asymmetric-TTL approach. A result where NEITHER comparison cleared min_coverage on either side (the "inconclusive_length_mismatch" outcome) expires after inconclusive_ttl_days and is retried on the next call, since new, shorter GenBank deposits for either species could change that answer. Any other result is cached indefinitely. A cache HIT still prints the identical narrative summary a fresh call would (unless verbose = FALSE), so repeated calls lose no output. Set cache_dir = NULL to disable caching entirely.

### investigate_flagged_accessions(accessions, species = NULL, max_related = 30L, method = c("remote", "local"), database = "nt", score_range = 8, min_score = 70, max_hits = 20L, submission_window = 5L, min_coverage = 0.5, max_length_ratio = 3, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), inconclusive_ttl_days = 30, ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""), verbose = TRUE)

Deep-Dive Verification for a Batch of Flagged Reference Accessions

The natural 'investigate_flagged_accessions()' (plural) batch wrapper 'investigate_flagged_accession()''s own docs point at (Question 3, item 2): runs the identical per-accession investigation over a whole list, but shares a single in-memory NCBI-search lookup across the batch (so a 'listed_species' or 'disagreeing_taxon' repeated across several independently-flagged accessions is only fetched from NCBI once, not once per accession) and shares the same persistent cache 'investigate_flagged_accession()' itself uses - calling this after already having called ...

| Param | Required | Default | Doc |
|---|---|---|---|
| accessions | yes |  | Character vector of flagged accessions to investigate. Not deduplicated automatically (each is looked up in the persistent cache independently, so a duplicate is cheap -- a cache hit after the first occurrence -- rather than an error). |
| species | no | NULL | Character vector the same length as accessions, or NULL (default, every accession's species is fetched from its own GenBank record). A single accession's own override may be NA to fall back to fetching that one accession's species while other elements stay overridden. |
| max_related | no | 30L | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| method | no | c("remote", "local") | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| database | no | "nt" | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| score_range | no | 8 | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| min_score | no | 70 | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| max_hits | no | 20L | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| submission_window | no | 5L | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| min_coverage | no | 0.5 | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| max_length_ratio | no | 3 | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| inconclusive_ttl_days | no | 30 | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| ncbi_api_key | no | Sys.getenv("NCBI_API_KEY", unset = "") | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |
| verbose | no | TRUE | As in investigate_flagged_accession() -- applied uniformly across the whole batch (not per-accession). |

**Value:** A named list (names = 'accessions'), one element per accession, each in the same shape 'investigate_flagged_accession()' returns.

#### Not the same as cluster-level mislabel detection

This function shares WORK across a batch (search results, cache entries) -- it does not look for cross-accession PATTERNS (e.g. several independently-flagged accessions all disagreeing toward the same species). That is a separate, higher-value, not-yet-designed idea (see the reentry prompt's Question 3, item 3) -- deliberately out of scope here.

### join_event_site_metadata(detections, site_metadata, event_col = "event_id", id_col = "observation_id", lat_col = "lat", lon_col = "lon", observed_on_col = "observed_on", control_samples = NULL)

Join Event-Level Detections to a Site Metadata Table

Produces a 'site_df' suitable for 'build_site_table' from any event-level detections table (one row per 'id_col' x 'event_col' pair actually observed) and a separately-maintained site metadata table ('event_col' plus site attributes). This is the same underlying operation for every data-type pathway that lacks embedded site info - DNA/BLAST (Reads-table sample columns) and acoustic (recording/ device identifiers) both reduce to "join an event identifier against a metadata table of where/when that event happened" - so one function serves both rather than duplicating the join per pathway.

| Param | Required | Default | Doc |
|---|---|---|---|
| detections | yes |  | Data frame. One row per (id_col, event_col) pair that was actually observed -- e.g. a Reads-table already pivoted to long format and filtered to n_reads > 0 (DNA/BLAST), or a BirdNET match object's own observation_id/source_file pairs (acoustic, already one row per detection window). Must contain id_col and event_col. |
| site_metadata | yes |  | Data frame maintained separately from the detections table -- one row per event_col value, with at least lat_col/lon_col columns and optionally observed_on_col. This is the same kind of lookup table already used to identify blank/control samples (e.g. BLANKS_MARCH, BLANKS_AUG in PtConceptionWorkflow_12S.R), generalized to carry site coordinates and collection date instead of (or in addition to) blank status. |
| event_col | no | "event_id" | Character. Join key column name, present in both detections and site_metadata. Default "event_id". |
| id_col | no | "observation_id" | Character. Observation ID column in detections. Default "observation_id". |
| lat_col | no | "lat" | Character. Latitude/longitude column names in site_metadata. Default "lat" / "lon". |
| lon_col | no | "lon" | Character. Latitude/longitude column names in site_metadata. Default "lat" / "lon". |
| observed_on_col | no | "observed_on" | Character. Collection-date column name in site_metadata, or NULL if not available. Default "observed_on". |
| control_samples | no | NULL | Character vector of event_col values to exclude before joining (blanks/controls are not real site detections). Default NULL (no exclusion). |

**Value:** A tibble in the long-format shape 'build_site_table''s 'site_df' argument expects: 'id_col', 'lat', 'lon', 'observed_on' ('NA' if 'observed_on_col = NULL'), plus 'event_col' retained for traceability. May have more than one row per 'id_col' value - this is the correct shape for an 'id_col' value (e.g. a sequence ASV) genuinely detected at more than one real event's site. Rows whose 'event_col' value has no matching 'site_metadata' row get 'NA' 'lat'/'lon', with a warning naming them.

### match_driving_accessions(match_df, score_col = "score_original", obs_col = "observation_id", species_col = "species", accession_col = "accession")

Which Reference Accessions Ever Drive a Likelihood?

Returns the accessions that are the max-scoring accession of their species for at least one observation (ties kept). 'TaxaLikely::evaluate_likelihoods()' reads the per-species best match, so every other accession never drives a likelihood and no verdict on it can change an assignment. This is a COST FILTER for the BLAST screen ('evaluate_reference_accessions()'), not a change to the match object: on the real PtConception 12S match object it keeps 709 of 995 candidate accessions.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. A standardized match object with the four columns named below. |
| score_col | no | "score_original" | Character. Column names; defaults "score_original", "observation_id", "species", "accession". |
| obs_col | no | "observation_id" | Character. Column names; defaults "score_original", "observation_id", "species", "accession". |
| species_col | no | "species" | Character. Column names; defaults "score_original", "observation_id", "species", "accession". |
| accession_col | no | "accession" | Character. Column names; defaults "score_original", "observation_id", "species", "accession". |

**Value:** Character vector of accessions, exactly as they appear in 'match_df' (version suffixes untouched, so they key the same cache rows a plain 'unique(match_df$accession)' would), unique, in first-appearance order.

#### Details

RESTORED_* provenance accessions (from TaxaLikely::restore_suppressed_candidates()) are dropped -- they are not GenBank records and cannot be screened. The Mugu workflow did this by hand at its call site; it is done here once.

### read_animl_output(files, file_col = "FileName", species_col = "prediction", score_col = "confidence", common_name_col = NULL, n_candidates = NULL, min_confidence = 0, top_n = NULL, bbox_cols = NULL)

Read Animl Camera Trap Results into a Match Object

Reads one or more Animl (MegaDetector + SpeciesNet) result CSV files and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Paths to Animl result CSV files. Alternatively, a path to a directory: all *.csv files in that directory (non-recursive) are read. |
| file_col | no | "FileName" | Character. Name of the column containing the image file path or filename. Default "FileName" (Animl R package manifest format). |
| species_col | no | "prediction" | Character. Name of the column containing the species prediction (scientific name). Default "prediction". For wide-format outputs (multiple candidates per row), set n_candidates and this argument becomes the prefix (e.g., "pred" for pred1, pred2, ...). |
| score_col | no | "confidence" | Character. Name of the confidence column. Default "confidence". For wide-format outputs, this is used as the prefix (e.g., "score" for score1, score2, ...). |
| common_name_col | no | NULL | Character or NULL. Name of a common name column, if present. Default NULL (common name column set to NA). |
| n_candidates | no | NULL | Integer or NULL. If NULL (default), expects long format -- one row per image x candidate species, with species_col and score_col holding the prediction and confidence directly. If a positive integer, expects wide format -- one row per image crop with candidate columns named paste0(species_col, 1:n_candidates) and paste0(score_col, 1:n_candidates) (e.g., pred1/score1 through pred3/score3). The wide format is pivoted to long before filtering. |
| min_confidence | no | 0 | Numeric. Detections below this confidence are dropped. Default 0 (keep all). |
| top_n | no | NULL | Integer or NULL. If supplied, only the top n candidates (by confidence) within each image are retained. Default NULL (keep all). |
| bbox_cols | no | NULL | Character vector of length 2 or NULL. Names of the bounding-box width and height columns (normalized 0--1, as output by MegaDetector). Supply as a named vector c(w = "bbox_w", h = "bbox_h") or positionally c("bbox_w", "bbox_h"). When provided, coverage = bbox_w * bbox_h is computed and added to the output; this area fraction serves as an image-quality analog to BLAST qcovs and is accepted by TaxaLikely::evaluate_likelihoods(min_coverage=). Default NULL (no coverage column). |

**Value:** A data frame with one row per image x candidate species, containing: 'observation_id' Unique identifier derived from the image filename stem (path stripped, extension(s) stripped). Multiple rows with the same 'observation_id' represent alternative species candidates for the same image/crop - analogous to multiple BLAST hits per eDNA query or multiple BirdNET candidates per time window. 'score' Animl classifier confidence (0-1). Pass as 'score_col' to 'standardize_match_data()'. 'species' Species prediction as reported by Animl. May be '"empty"' (no animal detected), '"human"', or '"vehicle"' for non-wildlife detections - filter these out before proceeding. 'genus' Genus name (first word of 'species'). 'NA' for non-binomial labels such as '"empty"'. 'common_name' Common name from 'common_name_col', or 'NA' if that column is absent. 'source_file' Basename of the source CSV file.

#### Details

Animl output formats: The Animl R package (animl on CRAN; wraps MegaDetector + SpeciesNet) supports multiple export formats. Two are handled here:

Long format (default, n_candidates = NULL): one row per image crop x candidate species. Columns: FileName, prediction, confidence. This is the format produced when you export classification results row-by-row.

Wide format (n_candidates = 3): one row per image crop with top-N candidates in columns pred1/score1, pred2/score2, pred3/score3. Pass species_col = "pred", score_col = "score", n_candidates = 3.

Filtering non-wildlife detections: Animl assigns non-animal labels ("empty", "human", "vehicle") to images with no wildlife. Filter these before standardizing:

```
match_df <- read_animl_output("animl_results/") |>
  dplyr::filter(!species %in% c("empty", "human", "vehicle"))
```

observation_id encoding: Each image (or bounding box crop, if cropped images are used) is one observation_id. Multiple species candidates for the same image share the same observation_id, enabling TaxaLikely's gap metric (top-1 minus top-2 confidence) to operate correctly. A camera trap image with multiple detected individuals/species yields multiple crops from MegaDetector, each a separate observation_id -- if Animl encodes the crop index in the filename (e.g. IMG_001_crop1.jpg), these are handled automatically; if the same filename is reused across crops, they will collide under one observation_id (a warning() is issued when duplicate image basenames are detected in file_col).

Taxonomy: genus is derived as the first word of the species column. For the full taxonomic hierarchy (family, order), run TaxaTools::verify_taxon_names() on the species column after filtering, then re-run standardize_match_data().

Downstream workflow:

```
match_df <- read_animl_output("animl_results/", min_confidence = 0.5) |>
  dplyr::filter(!species %in% c("empty", "human", "vehicle")) |>
  standardize_match_data(
    observation_id_col = "observation_id",
    score_col          = "score",
    rank_system        = c("genus", "species")
  )
```

### read_birdnet_output(files, min_confidence = 0, top_n = NULL)

Read BirdNET-Analyzer Results into a Match Object

Reads one or more BirdNET-Analyzer result CSV files and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector of paths to BirdNET result CSV files (typically named recording.BirdNET.results.csv); a path to a directory (all *.BirdNET.results.csv files are read non-recursively); or a data frame already loaded into R. The data frame path accepts both the original BirdNET column names ("Start (s)", "Scientific name", etc.) and the R-mangled versions produced by read.csv() with check.names = TRUE ("Start..s.", "Scientific.name", etc.). A "File" column must be present (Gradio / web interface combined-CSV format) to derive observation_id stems; CLI per-recording CSVs should be passed as file paths rather than pre-loaded data frames. |
| min_confidence | no | 0 | Numeric. Detections below this confidence are dropped. Default 0 (keep all). BirdNET's own default threshold is 0.1. |
| top_n | no | NULL | Integer or NULL. If supplied, only the top n detections (by confidence) within each time window are retained. Default NULL (keep all detections per window). Setting top_n = 1 retains only the best species per window; top_n = 3 reproduces BirdNET's default output when the tool is run with --top_n 3. |

**Value:** A data frame with one row per file x time-window x detected species, containing: 'observation_id' Unique identifier combining file stem and time window: '"{file_stem}_{start_s}-{end_s}"', with 'start_s'/'end_s' formatted to a fixed 1 decimal place so the same window produces the same ID across platforms/R versions. Pass as 'observation_id_col' to 'standardize_match_data()'. 'score' BirdNET confidence (0-1). Pass as 'score_col' to 'standardize_match_data()'. 'species' Full scientific binomial as reported by BirdNET. 'genus' Genus name (first word of 'species'); 'NA' for non-standard binomial formats. 'common_name' English common name. 'start_s' Detection window start time in seconds. 'end_s' Detection window end time in seconds. 'source_file' For the file-path input path, the basename of the source BirdNET result CSV. For the combined/Gradio data-frame input path, there is no CSV path to report (the data frame was already loaded before being passed in); this is instead the audio filename stem from the 'File' column, which may equal that column's own value and should not be assumed to be a CSV filename.

#### Details

BirdNET output formats: Two formats are supported:

CLI format (recommended): BirdNET-Analyzer (v2.x) run from the command line produces one CSV per audio file, typically named recording.BirdNET.results.csv, with columns Start (s), End (s), Scientific name, Common name, Confidence. The recording identity is encoded in the CSV filename and used as the observation_id stem. Pass a directory of these files or a character vector of paths.

Combined format: The BirdNET web interface (Gradio) and some third-party tools export a single CSV covering all recordings, with an additional File column containing the audio file path. When a File column is present, the observation_id stem is derived from the audio filename in that column rather than the CSV filename, so detections from different recordings remain distinct even in a single combined export -- except when two different recordings happen to share the same basename (e.g. recording.wav from different directories), which produces colliding observation_id stems; a warning() is issued when this is detected in the File column.

Only the default CSV output (--rtype csv, or the equivalent legacy default) is supported. BirdNET-Analyzer v2.4+'s --rtype flag can produce other formats (Audacity, R, kaleidoscope, table); passing one of those files here will fail the required-column check with an uninformative column list rather than a format-specific error. Per-recording metadata some BirdNET output modes include (latitude/longitude, week number, sensitivity) is not read or preserved.

Each row is one candidate species detection within a 3-second window (BirdNET's default segment length). Multiple rows per window occur when BirdNET returns top-N results.

observation_id encoding: Each time window in each recording is one observation_id. Multiple detections within the same window share the same observation_id (analogous to multiple BLAST hits per eDNA query). The gap metric in TaxaLikely is computed as the difference between the top-1 and top-2 confidence scores within each window -- so retaining multiple detections per window is important for model training.

Taxonomy: genus is derived as the first word of BirdNET's scientific name (NA for non-standard binomial formats such as hybrid notations or undescribed-species placeholders). species is the full binomial. For the full taxonomic hierarchy (family, order, class), run TaxaTools::verify_taxon_names() and convert_taxonomy_backbone() on the species column after standardization, then re-run standardize_match_data().

Downstream workflow:

```
match_df <- read_birdnet_output("birdnet_results/", min_confidence = 0.1) |>
  standardize_match_data(
    observation_id_col = "observation_id",
    score_col          = "score",
    rank_system        = c("genus", "species")
  )
```

### read_inaturalist_cv_output(files, score_type = c("combined_score", "score"), min_confidence = 0, top_n = NULL)

Read iNaturalist Computer Vision API Results into a Match Object

Reads one or more saved JSON files from the iNaturalist computer vision API and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Paths to iNaturalist CV JSON files. Alternatively, a path to a directory: all *.json files in that directory (non-recursive) are read. |
| score_type | no | c("combined_score", "score") | Character. Which score to use from the API response. "combined_score" (default) incorporates community identification frequency and is generally more calibrated. "score" is the raw computer-vision softmax score. |
| min_confidence | no | 0 | Numeric. Detections below this score are dropped. Default 0 (keep all). |
| top_n | no | NULL | Integer or NULL. If supplied, only the top n candidates (by score) within each image are retained. Default NULL (keep all). |

**Value:** A data frame with one row per image x candidate taxon, containing: 'observation_id' Unique identifier derived from the JSON filename stem (the name you gave the saved response file, ideally the image filename stem). 'score' iNaturalist CV score, passed through unchanged from the saved JSON's 'score_type' field. The live API returns scores on iNaturalist's 0-100 softmax convention (candidates for one image sum to approximately 100, not 1) - confirmed directly against the real API (see 'score_image_inat()''s matching @return note); do not assume a 0-1 scale or rescale before passing to 'TaxaLikely::evaluate_likelihoods()'. 'species' Scientific name (binomial) if the API returned a species-rank taxon; coarser name otherwise. 'genus' Genus name (first word of 'species'). 'NA' for non-binomial labels. 'common_name' Common name from the API response, or 'NA'. 'taxon_rank' Rank reported by the API (e.g., '"species"', '"genus"'). Useful for filtering to species-only suggestions. 'source_file' Basename of the source JSON file.

#### Details

Each JSON file should be the raw API response for one image, saved to disk after calling the iNaturalist API endpoint POST https://api.inaturalist.org/v1/computervision/score_image -- confirmed live and working (returning HTTP 200 with real results) as of this package's score_image_inat(), which calls the same v1 endpoint directly rather than saving JSON to disk first. See the @details section for a minimal API call example for the save-to-disk path this function reads.

Saving API responses: Each JSON file must be the API response for exactly one image. Name the file using the image stem so that observation_id is interpretable downstream:

```
# Requires httr2 and jsonlite
img_path <- "field_images/IMG_001.jpg"
resp <- httr2::request("https://api.inaturalist.org/v1") |>
  httr2::req_url_path("/computervision/score_image") |>
  httr2::req_body_multipart(
    image    = curl::form_file(img_path),
    jwt      = your_inat_api_token   # from inaturalist.org
  ) |>
  httr2::req_perform()
json_path <- sub("\\.jpg$", ".json", img_path)
writeLines(httr2::resp_body_string(resp), json_path)
```

Then: read_inaturalist_cv_output("field_images/"). The endpoint is rate-limited (documented at 60 requests/minute for authenticated users); pace calls accordingly when generating many JSON files in a batch.

Species rank filtering: iNaturalist CV returns suggestions at any rank (species, genus, family, ...). Filter before standardizing:

```
match_df <- read_inaturalist_cv_output("inat_results/") |>
  subset(taxon_rank == "species") |>
  standardize_match_data(
    observation_id_col = "observation_id",
    score_col          = "score",
    rank_system        = c("genus", "species")
  )
```

### read_sequence_table(input_data, sequence_col = "sequence", observation_id_col = NULL, abundance_cols = NULL, taxonomy = NULL, header_format = "none", id_prefix = "ASV")

Read Sequence Data into a Tidy ASV Table

Converts a DADA2 sequence table (matrix), a FASTA file, or a data frame (e.g., from a sequencing provider's CSV) into a tidy data frame with one row per unique sequence.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_data | yes |  | One of: A DADA2 sequence table (matrix with samples as rows and DNA sequences as column names) A path to a FASTA file A DNAStringSet object from Biostrings A data frame containing at least a sequence column (e.g., output from a sequencing provider). See Details for how abundance is computed. |
| sequence_col | no | "sequence" | For data frame input: name of the column containing DNA sequences. Default "sequence". Matching is case-insensitive (all column names are lowercased internally for matching), though the returned columns other than the four core ones are lowercased in the output regardless of their original casing in input_data. |
| observation_id_col | no | NULL | For data frame input: name of an existing observation/ESV identifier column to use as asv_id. If NULL (default), sequential IDs are generated using id_prefix. |
| abundance_cols | no | NULL | For data frame input: character vector of column names containing per-sample read counts to sum for total abundance. If NULL (default), numeric columns that are not taxonomy or metadata are auto-detected against an internal exclusion list (case-insensitive exact match against standard taxonomy ranks plus common ID/score column names -- see .non_abundance_col_names in the package source for the exact list) and whose VALUES look like counts (non-negative and whole). If no abundance columns are found, abundance is set to 1 per row. A message() reports which columns were summed and which numeric columns were skipped by name; a warning() names any skipped on their values. Auto-detection cannot be made complete, so prefer abundance_cols. Name-based exclusion misses a provider's own column naming, and value-based screening cannot distinguish a read count from any other non-negative integer -- a BLAST bitscore passes it. Demonstrated on a three-row table: a true abundance of 13/7/5 came back as 562/404/607 once pident, bitscore and evalue were summed in. Both screens are now applied and both those columns are excluded by name, but an integer metric under an unrecognised name would still be summed. Passing abundance_cols explicitly is the only way to be certain. |
| taxonomy | no | NULL | Optional data frame with taxonomy for each sequence. Must contain a column named "sequence" (for DADA2/DNAStringSet input, matched against the sequence itself) or "accession" (for FASTA input, matched against the header's first whitespace-delimited token). See Details. Ignored for data frame input (taxonomy columns are retained directly). |
| header_format | no | "none" | For FASTA input only: how to parse taxonomy from sequence headers. "semicolon" expects accession;kingdom;phylum;class;order;family;genus;species. "none" (default) does not parse headers. |
| id_prefix | no | "ASV" | Character prefix for generated ASV identifiers. Default "ASV". |

**Value:** A data frame with columns: asv_id Unique identifier (e.g., "ASV_001") sequence DNA sequence string length Sequence length in base pairs abundance Total read count across all samples If taxonomy is provided (via 'taxonomy' argument, parsed from FASTA headers, or present in a data frame input), taxonomy columns are appended. For FASTA/'DNAStringSet' input with 'header_format = "none"' (the default), an 'accession' column is also added (the header's first whitespace-delimited token) - this column drives taxonomy joining via the 'taxonomy' argument's '"accession"' key.

#### Details

DADA2 input: The standard DADA2 sequence table is a matrix where rows are samples, columns are ASV sequences (the column names are the literal DNA strings), and cells are integer read counts. read_sequence_table() collapses across samples to get total abundance per unique sequence. Rows are expected to be samples and columns sequences (DADA2's own convention); a transposed OTU-table-style matrix (rows = OTUs/ASVs, columns = samples, as used by QIIME2's biom format or mothur shared files) is not auto-detected and will be misread.

FASTA input: Accepts a file path (extensions .fasta, .fa, .fna, .fas) or a Biostrings::DNAStringSet object. Abundance is set to 1 per sequence unless the header contains abundance information (e.g., ;size=42). Sequences are not validated to contain only IUPAC nucleotide characters; a warning() is issued (not an error) when non-IUPAC characters or duplicate sequences are found.

Data frame input: Accepts any data frame with a column containing DNA sequences. Common sources include provider ASV/ESV tables with sample read counts in separate columns (e.g. Jonah Ventures tab+taxa CSV files). Abundance is computed by summing across abundance_cols. If not specified, the function auto-detects numeric columns that are not standard taxonomy or metadata columns -- see @param abundance_cols for the auto-detection rule. Taxonomy columns (kingdom, phylum, class, order, family, genus, species) and other non-numeric columns are retained in the output.

Taxonomy: Can be supplied three ways:

- Via the taxonomy argument (data frame with a sequence or accession column for joining)

- Parsed from FASTA headers with header_format = "semicolon"

- Directly present in a data frame input (retained automatically)

### read_speciesnet_output(files, min_confidence = 0, top_n = NULL, include_coverage = FALSE, min_detection_conf = 0)

Read SpeciesNet Batch Classification Results into a Match Object

Reads one or more real SpeciesNet CLI ('google/cameratrapai', python -m speciesnet.scripts.run_model --predictions_json=...) batch prediction JSON files and returns a tidy data frame in match object format, ready for 'standardize_match_data()' and downstream TaxaLikely processing.

| Param | Required | Default | Doc |
|---|---|---|---|
| files | yes |  | Character vector. Paths to SpeciesNet predictions_json output files. Alternatively, a path to a directory: all *.json files in that directory (non-recursive) are read. A single file's top-level predictions array may cover many images. |
| min_confidence | no | 0 | Numeric. Candidates below this classification score are dropped. Default 0 (keep all). |
| top_n | no | NULL | Integer or NULL. If supplied, only the top n candidates (by score) per image are retained -- SpeciesNet's own classifier already returns at most 5. Default NULL (keep all up to 5). |
| include_coverage | no | FALSE | Logical. If TRUE, adds a coverage column (bounding-box area fraction, bbox_w * bbox_h) and a detection_conf column, taken from the image's highest-confidence MegaDetector "animal" detection (SpeciesNet detection category "1") -- an image-quality analog to BLAST qcovs, matching read_animl_output()'s bbox_cols convention. NA for images with no qualifying detection. Default FALSE. |
| min_detection_conf | no | 0 | Numeric. Only used when include_coverage = TRUE: detections below this MegaDetector confidence are not eligible to be the representative detection. Default 0. |

**Value:** A data frame with one row per image x candidate species, containing: 'observation_id' Unique identifier derived from the image filename stem ('filepath', path stripped, extension(s) stripped). 'score' SpeciesNet classifier confidence (0-1) for this candidate, from the RAW top-5 'classifications' block - pre-geofencing, pre-taxonomic-rollup. This is deliberately NOT the same as 'ensemble_prediction_score' (see @details). 'species', 'genus', 'family', 'order', 'class' Parsed from SpeciesNet's own uuid;class;order;family;genus;species;common_name label string. Any of these may be 'NA' - SpeciesNet's own classifier taxonomy has 2000+ labels spanning every rank from class down to species. 'species' is the full binomial (genus + epithet, genus capitalized); the raw label's own species field is the epithet only. 'common_name' Common name from the label string, or the non-taxonomic label itself ('"animal"', '"blank"', '"vehicle"', '"human"') when no taxonomic rank is populated. 'taxon_rank' Finest populated rank among 'species'/'genus'/ 'family'/'order'/'class'; 'NA' for a non-taxonomic candidate. 'ensemble_prediction', 'ensemble_prediction_score', 'ensemble_prediction_source' SpeciesNet's own final answer for the WHOLE IMAGE (constant across every candidate row for that image) - the label string's own common name, plus the ensemble's confidence and which internal component produced it (e.g. '"classifier"', '"detector"', '"geofence"'). Kept as reference/diagnostic metadata; NOT used to build 'species'/'score' above - see @details. 'lat', 'lon', 'country' From the prediction's optional 'latitude'/'longitude'/'country' fields, when SpeciesNet was run with geographic context. 'NA' otherwise. Feed directly to 'build_site_table()' (already in the canonical 'lat'/'lon' names). 'coverage', 'detection_conf' Only present when 'include_coverage = TRUE'; see that parameter. 'source_file' Basename of the source JSON file.

#### Details

Why classifications, not prediction: SpeciesNet's ensemble deliberately rolls a prediction up to genus/family/order/class/kingdom whenever species-level confidence is insufficient (Markoff & Galaktionovs 2025, arXiv:2510.14594 -- precision over recall by design). The raw top-5 classifications block is the classifier's OWN candidate list, computed before that rollup and before geofencing -- it still carries species-level signal that the ensemble's own prediction field has already discarded. This function treats classifications as the primary multi-candidate source (mirroring blast_sequences()/ read_animl_output()'s multiple-hypotheses-per-query shape) precisely so that species-level candidates reach TaxaLikely/TaxaAssign's own prior-informed resolution instead of being silently pre-resolved by SpeciesNet's conservative rollup. ensemble_prediction/ ensemble_prediction_score are retained only as reference metadata (e.g. to compare against what TaxaID's own posterior later resolves to), not as an alternative candidate source.

Filtering non-wildlife detections: SpeciesNet assigns non-taxonomic labels ("animal", "blank", "human", "vehicle") when no wildlife taxon is identified, and a "no cv result" placeholder when the classifier itself failed. All of these have taxon_rank = NA. Filter before standardizing:

```
match_df <- read_speciesnet_output("speciesnet_predictions.json") |>
  dplyr::filter(!is.na(taxon_rank))
```

Running SpeciesNet:

```
pip install speciesnet
python -m speciesnet.scripts.run_model \
  --folders /path/to/images \
  --predictions_json speciesnet_predictions.json
```

Then:

```
match_df <- read_speciesnet_output("speciesnet_predictions.json") |>
  dplyr::filter(!is.na(taxon_rank)) |>
  standardize_match_data(
    observation_id_col = "observation_id",
    score_col          = "score",
    rank_system        = c("class", "order", "family", "genus", "species")
  )
```

Label format: SpeciesNet's label strings are confirmed directly against the shipped taxonomy file (data/model_package/taxonomy_release.txt in google/cameratrapai): uuid;class;order;family;genus;species;common_name, e.g. "...;amphibia;anura;bufonidae;rhinella;marina;cane toad". Any of the 5 taxonomic fields may be empty (coarser rollup); this function normalizes both an empty field and the literal "no cv result" placeholder to NA.

### refine_reference_verdicts(evaluation, cache_dir = NULL, pair_table = NULL, rank_system = TaxaTools::standard_ranks, min_congruent_rank = "family", top_n = 5L, hierarchy_incongruent_threshold = 0.5, min_independent_partners = 3L, min_partner_weight = 0, max_iter = 10L, tol = 1e-04, verbose = TRUE, local_corroboration = NULL, ...)

Re-run Reference Verdicts With Each Partner Weighted by Its Own Trustworthiness

'evaluate_reference_accessions()''s verdict is a vote over an accession's closest independent BLAST neighbours in which every neighbour counts exactly once, however dubious that neighbour's own label is. This function re-runs that vote from the cached per-partner votes, scaling each partner's contribution by its own 'label_confidence', and iterates to a fixpoint - because discounting a partner changes both the numerator and the denominator of everyone else's vote, which can flip verdicts in both directions.

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluation | yes |  | Data frame. Output of evaluate_reference_accessions(). label_confidence/reference_action are computed via score_reference_labels() if absent. |
| cache_dir | no | NULL | Character or NULL. The same cache_dir evaluate_reference_accessions() was called with; its reference_pair_cache.rds supplies the per-partner votes. Ignored when pair_table is supplied directly. |
| pair_table | no | NULL | Data frame or NULL. The per-partner votes, if held in memory rather than on disk -- columns id_x, id_y, p_match (0-1), pair_finest_common_rank. |
| rank_system | no | TaxaTools::standard_ranks | Character vector (default TaxaTools::standard_ranks), coarse to fine -- must be the ladder the pair table's pair_finest_common_rank was computed against. |
| min_congruent_rank | no | "family" | The vote parameters, matching evaluate_reference_accessions()'s own defaults. Pass whatever that call used. |
| top_n | no | 5L | The vote parameters, matching evaluate_reference_accessions()'s own defaults. Pass whatever that call used. |
| hierarchy_incongruent_threshold | no | 0.5 | The vote parameters, matching evaluate_reference_accessions()'s own defaults. Pass whatever that call used. |
| min_independent_partners | no | 3L | The vote parameters, matching evaluate_reference_accessions()'s own defaults. Pass whatever that call used. |
| min_partner_weight | no | 0 | Numeric (default 0). Floor on a discounted partner's weight; 0 means an accession resolved to reference_action == "remove" stops voting entirely. |
| max_iter | no | 10L | Integer (default 10L). Iteration cap. |
| tol | no | 1e-04 | Numeric (default 1e-4). Converged when no accession's label_confidence moves by more than this. |
| verbose | no | TRUE | Logical (default TRUE). |
| local_corroboration | no | NULL | Data frame or NULL (default). Forwarded to score_reference_labels(); the same veto (a locally-corroborated "remove" becomes "inspect") is applied to reference_action_trust. |
| ... | yes |  | Passed to score_reference_labels() (margin_scale, margin_cap, the three action thresholds) -- use the SAME values here as anywhere else in a pipeline, or the refined and unrefined columns are not comparable. |

**Value:** 'evaluation' with these columns added: 'hierarchy_flag_trust', 'label_confidence_trust', 'reference_action_trust', 'frac_below_min_congruent_rank_trust', 'n_effective_partners' (the weighted partner count, which is what 'min_independent_partners' is now compared against), and 'trust_refined' (logical - 'FALSE' where no pair data existed, in which case the *_trust columns simply repeat the unrefined values). 'attr(result, "trust_iterations")' and 'attr(result, "trust_converged")' record the fixpoint's own behaviour.

#### Details

Nothing is removed and nothing is overwritten: the refined verdicts arrive as parallel *_trust columns beside the originals.

#### What this needs, and what happens without it

The individual votes are not in the per-accession cache -- they are summarised and discarded from it. evaluate_reference_accessions() persists them separately, to a sidecar reference_pair_cache.rds, whenever cache_dir is not NULL. An accession evaluated with cache_dir = NULL has no pair rows, so it CANNOT be refined: it keeps its original verdict, trust_refined reads FALSE, and a message says how many accessions that applied to. Re-running evaluate_reference_accessions() on those accessions with a cache_dir set is what builds their pair rows; there is no way to reconstruct them without a fresh BLAST.

#### Determinism

Every iteration updates every accession simultaneously from the PREVIOUS iteration's confidences (a Jacobi sweep, not Gauss-Seidel), so the result does not depend on the order accessions appear in. The top_n slice breaks percent-identity ties by id_y rather than by input order, for the same reason.

#### What it does on real data

On the PtConception 12S screen the motivating case was Askoldia variegata (MT627596), the disagreeing partner in 4 of the 12 "incongruent" verdicts. Its own row reads "insufficient_independent_evidence" with a 100% agreeing hit and nothing disagreeing -- label_confidence 0.999. So the honest answer is that weighting does not discount it: it is an under-evaluated partner, not a likely error, and the disagreement it registers is a real family-level distinction in a thinly-covered clade. The mechanism is right and the cascade guard is doing its job; this particular accession was simply not the culprit it looked like.

### remove_incongruent_references(match_df, evaluation, remove_insufficient_evidence = FALSE, override_accessions = NULL, gate = c("action", "flag"))

Remove Confidently-Incongruent Reference Accessions from a Match Object

Filters a match data frame to remove rows whose reference accession was flagged '"incongruent"' by 'evaluate_reference_accessions()'. Deliberately conservative: only the confident '"incongruent"' verdict is dropped by default - '"insufficient_independent_evidence"' is ambiguous (may simply mean a sparsely-referenced region of the database, not a real problem) and is retained unless 'remove_insufficient_evidence = TRUE'.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_df | yes |  | Data frame. A standardized match object (from standardize_match_data()) containing an accession column. |
| evaluation | yes |  | Data frame. Output of evaluate_reference_accessions(). |
| remove_insufficient_evidence | no | FALSE | Logical (default FALSE). If TRUE, also removes accessions flagged "insufficient_independent_evidence". Applies under both gate settings -- reference_action can never be "remove" for that flag on its own (see score_reference_labels()'s @section Why "remove" also requires no corroboration anywhere), so this argument stays the only way to drop them. |
| override_accessions | no | NULL | Character vector of accession IDs (default NULL), or NULL to disable. Accessions listed here are NEVER removed, regardless of hierarchy_flag -- the automated counterpart to the @section Use flag_incongruent_references() first caution above. hierarchy_flag = "incongruent" alone cannot distinguish a genuine mislabel from a correctly-labeled record with poor marker resolution or thin corroborating coverage (a real confirmed case in this ecosystem: Stereolepis doederleini was flagged "incongruent" by a broad screen, then separately investigated and found to be exactly this -- not a real mislabel). resolve_review_overrides() derives this argument automatically from review_flagged_accessions()'s LLM second-look verdicts, so a caller can safely default to removing every flagged accession while still letting a specific, reviewed explanation override that default for the one accession it actually applies to -- rather than choosing between "remove everything, including real correctly- labeled records" and "remove nothing, unreviewed." Only ever rescues, never removes an accession hierarchy_flag would otherwise have kept. |
| gate | no | c("action", "flag") | Character, "action" (default) or "flag". "action" removes accessions whose reference_action is "remove"; "flag" removes every accession whose hierarchy_flag is "incongruent". Under "action", reference_action is computed on the fly via score_reference_labels() if evaluation does not already carry it. |

**Value:** The input 'match_df' with flagged rows removed. Unchanged if no flagged accessions are found.

#### Use flag_incongruent_references() first

This function is not the recommended default pipeline step -- see flag_incongruent_references()'s own @section Why flag-by-default, not drop-by-default for the real case illustrating why. Reach for this function deliberately, after reviewing hierarchy_flag alongside the identity diagnostics (best_agreeing_pident/best_disagreeing_pident/ congruent_evidence_exists_anywhere), not as an unreviewed default step.

#### The evidence gate is the default

gate = "action" (the default) removes an accession only when score_reference_labels() resolved it to reference_action == "remove" -- flagged "incongruent" AND uncorroborated anywhere AND below the confidence threshold -- rather than on hierarchy_flag == "incongruent" alone. hierarchy_flag is a majority vote over the top-N neighbours in which percent identity never appears, so in a thinly-covered clade it fires on correct references by construction. Measured on the real 995-accession PtConception screen: gate = "flag" removes 12 accessions behind 1,688 observations -- including cabezon (OK172573, 1,120 observations, agreeing hit at 100%) -- to catch the 4 (16 observations) that genuinely had no corroboration anywhere. gate = "action" removes exactly those 4.

#### This is a blacklist decision, not the whole signal

Even under gate = "action" this function consumes only a yes/no removal decision. The continuous signal (score_reference_labels()'s label_confidence) travels separately, via flag_incongruent_references(), and is meant for review. A likelihood-model covariate driven by it was evaluated and found not to help. Do not let this function's use become the only place the full evaluation object's signal is consulted.

### report_match(match_data, data_type = NULL, verbose = FALSE)

Generate a Report Section for Sequence Matching

Summarizes the match data produced by TaxaMatch into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| match_data | yes |  | Data frame. Match results from blast_sequences or standardize_match_data. Must contain at least observation_id and score_original -- the canonical raw score column name produced by standardize_match_data() (see the package's "Canonical Match Object" documentation), not score. A match_data lacking score_original is accepted without error but produces no score statistics and empty results text. |
| data_type | no | NULL | Character or NULL. One of "eDNA", "image", "acoustic". If NULL, auto-detected as "eDNA" when match_data has an accession or alignment_length column (both BLAST-specific); otherwise stays NULL and the methods/results text uses generic wording. There is currently no auto-detection for "image"/"acoustic" -- pass these explicitly. data_type also controls whether the results text formats scores as a percentage (see @return's results entry). |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing matching approach. results Template text summarizing match statistics, or 'NULL' when 'match_data' has neither 'score_original' nor a taxon-name column to summarize. Scores are formatted as a percentage only when 'data_type == "eDNA"' (percent identity is always 0-100 for BLAST); for '"image"'/'"acoustic"' (whose score scale varies by classifier - 0-1 for BirdNET/Animl, 0-100 for iNaturalist CV) the raw score value is reported unlabeled rather than guessing a scale. params Named list of matching parameters ('method', 'database', 'min_score', 'marker' when available). May contain additional fields passed through unchanged from 'attr(match_data, "report_params")' (e.g. 'n_samples' from 'blast_sequences()') whenever that attribute carries fields not already named above. statistics Named list of summary counts and scores.

### resolve_review_overrides(review_result, keep_explanations = c("poor_marker_resolution", "sister_family_thin_coverage", "hybrid_or_specimen_code_artifact"), min_confidence = c("high", "moderate"), resolution_rank = "order")

Derive Removal Overrides from an LLM Second-Look Review

Bridges 'review_flagged_accessions()''s LLM-based second-look verdicts to 'remove_incongruent_references()''s 'override_accessions' argument, automating a "remove everything flagged by default, but let a specific reviewed explanation override that default for the one accession it actually applies to" pipeline - rather than choosing between removing every flagged accession (including real, correctly-labeled records the raw BLAST verdict can't distinguish from a genuine mislabel) or removing nothing until every flag has been manually reviewed.

| Param | Required | Default | Doc |
|---|---|---|---|
| review_result | yes |  | Data frame. Output of review_flagged_accessions() (must have accession, accession_likely_explanation, accession_review_confidence columns). |
| keep_explanations | no | c("poor_marker_resolution", "sister_family_thin_coverage", "hybrid_or_specimen_code_artifact") | Character vector (default c("poor_marker_resolution", "sister_family_thin_coverage", "hybrid_or_specimen_code_artifact")) -- the accession_likely_explanation values that should override an automatic removal. Deliberately excludes "uncertain" from the default: an LLM verdict that is ITSELF uncertain should not automatically override a hard BLAST-based "incongruent" flag -- pass "uncertain" explicitly if you want to trust it too. "genuine_mislabel" is never included (that verdict CONFIRMS removal, it never overrides it). |
| min_confidence | no | c("high", "moderate") | Character vector (default c("high", "moderate")). Only a accession_review_confidence value in this set is trusted as an override -- a "low"-confidence review falls through to removal (the same conservative-default behavior as an unreviewed accession), even if its accession_likely_explanation is in keep_explanations. |
| resolution_rank | no | "order" | Character or NULL (default "order"). A "poor_marker_resolution" or "sister_family_thin_coverage" explanation only overrides a removal when the accession still agrees with its hits at this rank or finer (finest_common_rank): a marker's resolving power can only fail between close relatives. NULL disables the check, which is also skipped when review_result has no finest_common_rank column. |

**Value:** Character vector of accessions to pass directly as 'remove_incongruent_references(override_accessions = ...)'.

#### Real motivating case

A real GreatLakes match-candidate screen flagged Stereolepis doederleini (LC649807) hierarchy_flag = "incongruent". A separate, earlier investigation into this exact accession found it is very likely a correctly-labeled record with genuinely poor marker resolution at this rank, not a real mislabel -- exactly the ambiguity remove_incongruent_references()'s own @section Use flag_incongruent_references() first documents. This function is the automated version of applying that finding: run review_flagged_accessions() once, and any accession the LLM categorizes as something other than a genuine mislabel is kept, without needing a human to individually re-decide each one every time the pipeline re-runs.

### review_flagged_accessions(evaluated_df, hierarchy_flags = c("incongruent", "insufficient_independent_evidence"), include_non_species_resolved = TRUE, cache_dir = tools::R_user_dir("TaxaMatch", "cache"), llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), taxa_per_call = 10L, max_tokens = NULL, max_retries = 2L, pause_seconds = 1, verbose = TRUE, local_min_overlap = NULL)

LLM Second-Look Review of Flagged Reference Accessions

Sends 'evaluate_reference_accessions()''s flagged/borderline rows to an LLM for a free-text second look - the same "narrative-judgment layer added ON TOP of statistical flags, never replacing them, never auto-acting" pattern 'TaxaFlag::review_assignments()' already established for posterior taxonomic assignments. The LLM never re-decides 'hierarchy_flag' - it adds what the statistical check structurally cannot: recognizing a known hybrid-cross name (e.g. '"Ctenopharyngodon idella x Megalobrama amblycephala"', a known Chinese aquaculture hybrid), an informal specimen code (e.g. ...

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluated_df | yes |  | Data frame -- evaluate_reference_accessions()'s own output. Must contain accession, listed_taxon, hierarchy_flag, one row per accession. Every other column used in the prompt (finest_common_rank, best_agreeing_pident, best_disagreeing_pident, best_disagreeing_taxon, congruent_evidence_exists_anywhere, congruent_evidence_best_pident, taxonomy_resolution_source, listed_taxon_is_species, n_independent_top_matches, n_top_matches_available, frac_independent_below_min_congruent_rank) is optional -- silently omitted from the prompt when absent, matching TaxaFlag::review_assignments()'s established convention for optional upstream columns. A duplicated accession value triggers a warning() (see Details) rather than an error, since a caller may have joined this onto a match object by mistake. |
| hierarchy_flags | no | c("incongruent", "insufficient_independent_evidence") | Character vector of hierarchy_flag values to review. Default c("incongruent", "insufficient_independent_evidence"). |
| include_non_species_resolved | no | TRUE | Logical (default TRUE). Also review any row with listed_taxon_is_species == FALSE, regardless of hierarchy_flag -- a structurally different, orthogonal problem the evaluation guide documents separately (see its own "listed_taxon_is_ species = FALSE" section). Silently ignored if listed_taxon_is_species is absent from evaluated_df. |
| cache_dir | no | tools::R_user_dir("TaxaMatch", "cache") | Character or NULL. Default tools::R_user_dir("TaxaMatch", "cache") (same default/convention as evaluate_reference_accessions() and investigate_flagged_accession()). Persistent, accession-keyed cache of LLM reviews -- an accession already reviewed with UNCHANGED inputs (see @section Caching below) is served from cache instead of making a real LLM call. Set NULL to disable caching entirely (every call re-reviews every in-scope accession). |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Function. LLM provider function with signature function(prompt_str, ...). Default TaxaTools::call_api. Known footgun: call_api()'s provider auto-detection is set up by TaxaTools's own .onAttach(), which only runs via library(TaxaTools) -- a fully-namespaced call (TaxaTools:: everywhere, no library()) never triggers it, and call_api() silently falls back to degraded/uniform output rather than erroring. Pass llm_fn explicitly if every review comes back suspiciously uniform, e.g. function(p) TaxaTools::call_api(p, provider = "anthropic"). |
| taxa_per_call | no | 10L | Integer. Maximum accessions per LLM call. Default 10L. |
| max_tokens | no | NULL | Integer or NULL. Forwarded as llm_fn(prompt, max_tokens = max_tokens) whenever supplied. Default NULL -- llm_fn's own default applies. |
| max_retries | no | 2L | Integer (default 2L). A truncated, empty, or unparseable batch response is automatically split in half and retried (a smaller batch requests a proportionally shorter response) up to this many times, matching review_assignments()'s own retry mechanism. |
| pause_seconds | no | 1 | Numeric (default 1). Seconds to pause between LLM calls. |
| verbose | no | TRUE | Logical (default TRUE). Print progress messages. |
| local_min_overlap | no | NULL | Numeric in (0, 1] or NULL (default). The min_overlap corroborate_references_locally() was run with, quoted in the prompt's local-corroboration line ("best identity X% over >= 80% of the amplicon"). NULL reads it from attr(evaluated_df, "local_corroboration_params") when score_reference_labels() left one there, and otherwise words the line without a number. Only matters when evaluated_df carries local_n_independent_conspecific/local_best_independent_pident. |

**Value:** 'evaluated_df' with 4 columns appended ('NA' for out-of-scope rows): 'accession_likely_explanation' One of '"genuine_mislabel"', '"poor_marker_resolution"', '"sister_family_thin_coverage"', '"hybrid_or_specimen_code_artifact"', '"uncertain"' - the LLM's own categorization of WHY the accession was flagged, never a re-decided 'hierarchy_flag'. 'accession_review_confidence' '"high"' / '"moderate"' / '"low"'. 'accession_review_comment' Free-text note, or 'NA'. 'accession_review_cache_hit' Logical. 'TRUE' if this row's review was read from 'cache_dir' rather than freshly generated this call (always 'FALSE', never 'NA', for an in-scope row when 'cache_dir = NULL'). 'NA' for an out-of-scope row. Also carries 'attr(result, "llm_prompts")' - a named list of the exact prompt string sent for each LLM call actually made this call (named by batch number, with an '"a"'/'"b"' suffix per retry sub-batch split), matching 'review_assignments()''s own convention. A batch entirely served from cache makes no LLM call at all and so has no entry here.

#### Prompt content, lifted from the evaluation guide, not re-derived

The prompt teaches the LLM inst/reference_accession_evaluation_guide.md's own 5-category decision framework (genuine mislabel / poor marker resolving power / sister-family-thin-coverage artifact / hybrid-cross or specimen-code artifact / non-species-resolved partner) using that guide's own worked real examples (Stereolepis doederleini, Abylopsis eschscholtzii, NC_028197/"Serranidae sp. JL-2015") -- the same reasoning a careful human reviewer already applies by hand. Keep the guide updated (and this function's prompt in sync with it) if real usage surfaces a case class the guide doesn't yet cover.

#### What the LLM outputs -- and does NOT output

A free-text accession_review_comment plus two small structured fields (accession_likely_explanation, accession_review_confidence) -- never a re-decided hierarchy_flag, and this function never calls remove_incongruent_references() or otherwise mutates the evaluation itself. This follows this ecosystem's own caution around a trusted_rank- style mechanism (TaxaLikely::evaluate_likelihoods()) that once recomputed/overrode an existing categorical verdict and was removed after a real ~30% mismatch between the hypothesis it was computed for and the one that actually won downstream: a mechanism that recomputes/overrides an existing categorical verdict is exactly the shape that broke there. A human reads accession_review_comment before acting on it.

#### Package placement

Lives in TaxaMatch, not TaxaFlag, deliberately. Every other reference- accession-quality function (evaluate_reference_accessions(), investigate_flagged_accession(), check_marker_mismatch(), flag_incongruent_references(), remove_incongruent_references()) already lives here and operates on this same output shape. TaxaMatch -> TaxaFlag is not currently a dependency edge in this ecosystem -- TaxaFlag::review_assignments() reviews post-assignment DETECTIONS (a structurally later pipeline stage, downstream of TaxaAssign); this reviews pre-assignment REFERENCE DATABASE quality, upstream of TaxaExpect/TaxaAssign entirely. No new dependency is needed to place it here either way: this function calls TaxaTools::call_api() the exact same way review_assignments() does, and TaxaMatch already depends on TaxaTools for several other reasons (is_plausible_binomial(), clean_taxon_names(), verify_taxon_names(), standard_ranks).

#### Scope (cost control)

Only reviews rows matching hierarchy_flags/include_non_species_resolved -- not the whole evaluated population. On the real GreatLakes Goal-2 population this reentry prompt was written against, the default scope selects 8 + 17 + 57 = 82 of 1,183 accessions (~7%), a tractable LLM batch size -- see the reentry prompt's own "Cost/scale" discussion.

#### Caching

An in-scope accession is served from cache_dir instead of a real LLM call when a cached review exists AND its stored content fingerprint (built from listed_taxon/hierarchy_flag/finest_common_rank/the identity diagnostics/taxonomy_resolution_source/ listed_taxon_is_species/the independence-filtering counts -- see .accession_review_fingerprint()) matches the CURRENT row in evaluated_df. Re-running evaluate_reference_accessions() on an accession and getting a genuinely different verdict or diagnostic value therefore triggers a fresh review automatically -- the cache never masks a real change, unlike a plain accession-keyed or TTL-based cache would. The cache is written incrementally, once per LLM batch actually sent (matching evaluate_reference_accessions()'s own per-chunk cache-write design) -- an interruption partway through a large review run only loses whatever batch was still in flight, not every batch completed so far.

### score_image_inat(image_path, lat = NULL, lng = NULL, observed_on = NULL, top_n = 10L, recursive = FALSE, api_token = Sys.getenv("INAT_API_TOKEN"))

Score images using the iNaturalist Computer Vision API

Submits one or more images to the iNaturalist CV API and returns a tidy match object with ranked taxon suggestions and associated scores. When latitude/longitude are supplied (via argument or EXIF), 'combined_score' reflects iNaturalist's geomodel prior; the ratio 'combined_score / vision_score' ('geo_prior_weight') recovers the implicit geographic prior weight for each taxon at that location. 'geo_prior_weight' is 'NA' when 'vision_score == 0' (a real case for taxa with very low vision-classifier confidence).

| Param | Required | Default | Doc |
|---|---|---|---|
| image_path | yes |  | Character. Path to a single JPEG or PNG image file, a character vector of image file paths, or a path to a directory. When a directory is given, all .jpg, .jpeg, and .png files are processed -- non-recursively by default; set recursive = TRUE to scan subdirectories. recursive is silently ignored when image_path is a file vector rather than a directory. |
| lat | no | NULL | Numeric. Latitude in decimal degrees (optional). When supplied, this value is used for all images and overrides any EXIF-derived latitude. Must be supplied together with lng. |
| lng | no | NULL | Numeric. Longitude in decimal degrees (optional). When supplied, this value is used for all images and overrides any EXIF-derived longitude. Must be supplied together with lat. |
| observed_on | no | NULL | Character. Observation date in "YYYY-MM-DD" format (optional). When supplied, used for all images and overrides EXIF-derived dates. |
| top_n | no | 10L | Integer. Number of top taxon suggestions to return per image. Default 10L. |
| recursive | no | FALSE | Logical. When image_path is a directory, also scan subdirectories recursively. Default FALSE. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. iNaturalist API token. Defaults to the INAT_API_TOKEN environment variable. Obtain a token by visiting https://www.inaturalist.org/users/api_token while logged in. |

**Value:** A tibble with up to 'top_n' rows per image (one per candidate taxon; some images may return fewer when the API has fewer suggestions), containing: 'observation_id' (image filename stem), 'taxon_name', 'taxon_name_rank', 'score_original' (identical to 'combined_score'; kept under the canonical pipeline name for compatibility with 'evaluate_likelihoods()'), 'genus', 'common_name', 'iconic_taxon_name', 'taxon_id', 'n_observations' (global iNat observation count for the taxon - not location-filtered), 'vision_score', 'combined_score', 'freq_score' (a thresholded presence indicator from the iNaturalist geomodel, not a raw frequency; see Details), 'geo_prior_weight' ('combined_score / vision_score'; the continuous geographic prior signal), 'lat', 'lng', 'observed_on' (per-image location/date metadata), and zero or more 'folder_1', 'folder_2', ... columns encoding the nested directory levels between the input base path and each image file. *Score scale:* all score columns are in iNaturalist's 0-100 softmax convention (scores across candidates sum to approximately 100 per image). Do not rescale to 0-1 before passing to 'TaxaLikely::evaluate_likelihoods()'.

#### Details

Score semantics: vision_score is the raw image classifier output (discriminative CNN, no location). combined_score approximates a Bayesian posterior by weighting vision_score by the geomodel prior (geo_prior_weight). freq_score is a thresholded presence indicator from the iNaturalist geomodel and is not a raw frequency. Neither score is a true likelihood in the Bayesian sense; combined_score is used as score_original because it is the most informative predictor when location is available.

EXIF extraction: When lat, lng, or observed_on are NULL, the function attempts to read these values from each image's EXIF metadata using the exifr package (if installed). Install with install.packages("exifr") and ensure ExifTool is available (see ?exifr::read_exif). When exifr is not available and no arguments are supplied, the API call omits location and date (vision score only; geo_prior_weight = 1).

Path metadata: Directory levels between the input base path and each image are output as folder_1, folder_2, ... columns. These may encode site, date, treatment, or other study design information embedded in a nested folder hierarchy (e.g., images/SiteA/2024-06-01/IMG_001.jpg yields folder_1 = "SiteA", folder_2 = "2024-06-01").

Taxonomy normalization: The CV API returns iNaturalist taxonomy. Before feeding the output into join_priors(), run TaxaMatch::convert_taxonomy_backbone() to remap iNat names to the GBIF backbone (or your prior backbone). The family column is not populated here because it is not returned by the CV API; use TaxaTools::fill_higher_ranks() to add it after backbone normalization.

Authentication: Tokens expire periodically. If you receive a 401 error, regenerate your token at https://www.inaturalist.org/users/api_token.

Rate limiting: Requests to non-final images are throttled to iNaturalist's documented authenticated-user limit of 60 requests/minute.

Known biases: the iNaturalist geomodel prior is trained on iNaturalist observation data, which carries well-known geographic and taxonomic biases (urban bias, observer hotspot bias, charismatic-species bias) -- combined_score may underweight rare or cryptic species that are genuinely present but underobserved on iNaturalist. The CV model itself is trained primarily on human-submitted wildlife photographs (close-range, well-lit, single subject); camera trap images (infrared, wide-angle, partially occluded or distant subjects) are out-of-distribution for it, and scores may be systematically lower or less well-calibrated than for standard photographs. Consider supplementing camera trap workflows with read_animl_output() (SpeciesNet), which is trained on camera trap data.

### score_reference_labels(evaluation, margin_scale = 1, margin_cap = 5, action_remove_below = 0.05, action_inspect_below = 0.25, action_caution_below = 0.75, overwrite = FALSE, local_corroboration = NULL)

Score Reference Labels: a Numeric Label Confidence and a Categorical Action

Adds two derived columns to an 'evaluate_reference_accessions()' result: 'label_confidence' (numeric, high = the listed label is more likely CORRECT) and 'reference_action' ('"keep"'/'"caution"'/'"inspect"'/ '"remove"'/'"untested"'). Evidence and action are deliberately separate columns - the same split this ecosystem already uses for 'TaxaFlag::observation_validity' (numeric) vs 'validity_flag' (categorical), and for 'TaxaHabitat::flag_institution_candidates()''s classify-then-review shape. The numeric grades the evidence; the categorical is for humans and for ...

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluation | yes |  | Data frame. Output of evaluate_reference_accessions() (or any data frame carrying its diagnostic columns -- a cache file read straight off disk works). |
| margin_scale | no | 1 | Numeric (default 1). Percent-identity points per unit of log-odds. Larger = the identity margin matters less relative to the vote. See @section Where the numbers come from. |
| margin_cap | no | 5 | Numeric (default 5). Caps \|d\|, and supplies the value used for the two one-sided cases (corroborated with nothing contradicting it; contradicted with nothing corroborating it anywhere). |
| action_remove_below | no | 0.05 | Numeric thresholds on label_confidence (defaults 0.05, 0.25, 0.75) separating "remove"/"inspect"/"caution"/"keep". |
| action_inspect_below | no | 0.25 | Numeric thresholds on label_confidence (defaults 0.05, 0.25, 0.75) separating "remove"/"inspect"/"caution"/"keep". |
| action_caution_below | no | 0.75 | Numeric thresholds on label_confidence (defaults 0.05, 0.25, 0.75) separating "remove"/"inspect"/"caution"/"keep". |
| overwrite | no | FALSE | Logical (default FALSE). TRUE recomputes and replaces label_confidence/label_identity_margin/reference_action (and the local-corroboration columns) if they are already present; FALSE errors instead, so a second call with different parameters can't silently produce a mixed-provenance table. |
| local_corroboration | no | NULL | Data frame or NULL (default). Output of corroborate_references_locally(). Joined by version-stripped accession. See @section Local corroboration. |

**Value:** 'evaluation' with seven columns added: 'label_confidence' Numeric in (0, 1). 'NA' for a row with no computed congruence at all ('"not_evaluated_oversized"', '"not_evaluated_wrong_marker"', or a fetch failure). *Named contract: this value CANNOT REACH 1*, by construction - the Jeffreys smoothing floors the disagreement fraction at '0.5/(n+1)', so even a perfectly corroborated multi-partner accession tops out just under 1 (e.g. '0.99939' for a real 5-partner case). Any future consumer reading this as a RATIO where 1 means "no adjustment needed" (e.g. a likelihood-covariate-style rescale) must normalize by the per-row achievable ceiling first, or it will silently adjust every candidate in the dataset - this is exactly the bug a prior attempt to use this column as a likelihood covariate hit before being removed entirely. 'label_identity_margin' Numeric, the capped 'd' in percent-identity points. 'NA' when the row carries no identity information of any kind. 'reference_action' '"keep"', '"caution"', '"inspect"', '"remove"', or '"untested"'. '"untested"' means NO USABLE EVIDENCE WAS OBTAINED, which covers two different routes there: the query was never submitted to BLAST ('"not_evaluated_oversized"', '"not_evaluated_wrong_marker"'), or it was submitted and came back with zero valid comparison partners ('n_independent_top_matches == 0'; included in this case - see @section No partners is not a coin flip). 'action_reason' '"vetoed_by_local_corroboration"' where a '"remove"' was downgraded to '"inspect"' by the local set, '"locally_corroborated_not_blasted"' for a skipped row, 'NA' otherwise. 'corroboration_source' '"blast"', '"local"', '"both"', or '"none"'. 'NA' for a row with no verdict at all. 'local_best_independent_pident' Percent identity (0-100) of the best independent local conspecific; 'NA' without a table. 'local_n_independent_conspecific' Its count; 'NA' without a table. Row count and order are unchanged.

#### Polarity

HIGH label_confidence means MORE confidence that the label is correct, i.e. LESS concern. This deliberately does NOT follow the ecosystem's *_risk/*_confusion_risk convention (where high = more concern), which is why the column is named label_confidence and not label_risk -- the name states the direction. It is on the same scale and polarity as score_likelihood and TaxaFlag::observation_validity, which is what a consumer that multiplies it into a weight actually needs.

#### No partners is not a coin flip

An accession with ZERO valid comparison partners (n_independent_top_matches == 0) has label_confidence = NA and reference_action = "untested", rather than the 0.500 the arithmetic would otherwise produce. With no partners, frac_independent_below_min_congruent_rank falls back to its 0.5 default and the identity margin is NA, so the formula reduces to plogis(qlogis(0.5) + 0). That is a prior with no data, not a measurement, and it lands in the "caution" band, asserting concern earned by an absence.

The rule keys on the partner COUNT, deliberately not on hierarchy_flag. An accession with 1-2 partners also reads "insufficient_independent_evidence", but it does have real evidence, and keying on the verdict would wrongly blank those too.

Some zero-partner rows are a max_hits truncation artifact rather than a property of the accession, and a larger max_hits can resolve some of them, but many stay genuinely thin. "untested" is the honest reading either way: we do not know.

#### Where the numbers come from

label_confidence is a pure function of columns evaluate_reference_accessions() already caches, so it applies to any existing cache with no .EVAL_REF_ACC_VERSION bump and no re-BLAST. Its formula is a log-odds sum of the existing Jeffreys-smoothed vote and the percent-identity margin the vote itself ignores:

```

logit(label_confidence) = logit(1 - frac_independent_below_min_congruent_rank) + d / margin_scale d = (best_agreeing_pident, else congruent_evidence_best_pident) - best_disagreeing_pident, capped to +/- margin_cap ```

margin_scale is the one free parameter: it says how many percent-identity points are worth one unit of log-odds. The default 1 is a stated convention, not a fitted value: at MiFish-U amplicon lengths (~170 bp) one percent identity is roughly 1.7 nucleotide differences, the granularity at which this ecosystem treats identity differences as discriminating at species level.

#### Why "remove" also requires no corroboration anywhere

reference_action == "remove" is gated on THREE conditions, not just a low label_confidence: the accession must be flagged "incongruent", have no corroborating evidence anywhere in the untruncated independence-filtered hit pool, AND score below action_remove_below. The corroboration test is a hard veto rather than another additive term because one corroborating record anywhere is qualitatively different from none: some independent submitter's sequence agrees with this label at family or finer. A threshold alone is not robust, because a borderline reference whose only corroboration sits just outside the top-n window would flip on any small change to margin_scale or action_remove_below. The veto keeps such a reference at "inspect" (surfaced for review, not deleted) while genuinely uncorroborated accessions are still "remove".

"remove" is unreachable for any flag other than "incongruent". "insufficient_independent_evidence" is retryable, not removable (it may simply mean a sparsely-referenced region of the database). "not_evaluated_oversized" and "not_evaluated_wrong_marker" were never submitted to BLAST. "locally_corroborated" was deliberately not submitted because the caller's own reference set already corroborates it; it reads "keep" with label_confidence = NA (there is no BLAST evidence to grade).

#### Local corroboration

provenance and the veto: When local_corroboration (corroborate_references_locally() output) is supplied, three things happen, and one deliberately does not. corroboration_source records where the corroboration for each label came from: "blast" (congruent_evidence_exists_anywhere), "local" (local_tier == "corroborated", or the row was skipped as "locally_corroborated"), "both", or "none". local_best_independent_pident and local_n_independent_conspecific carry the local numbers beside the BLAST ones. And a row that resolves to "remove" while the local set corroborates it is VETOED to "inspect", with action_reason = "vetoed_by_local_corroboration".

What does not happen: label_confidence stays the BLAST-only probability. Local evidence is not folded into it, on purpose, so a reviewer can see the two disagree (see evaluate_reference_accessions()'s @section Why the query is the primer-stripped amplicon). All four columns are present (NA/"none"-filled) even when no table is supplied, so downstream code can rely on them.

### standardize_match_data(data = NULL, observation_id_col, score_col, rank_system = NULL, coverage_col = NULL, col_map = NULL, lowercase_names = TRUE)

Standardize Raw Match Data to Canonical Match Object

Reads raw match data (from a data frame or file), renames the observation identifier and score columns to canonical names ('observation_id' and 'score_original'), auto-detects or validates taxonomic rank columns, and derives 'taxon_name' and 'taxon_name_rank' via 'TaxaTools::create_taxon_names()'.

| Param | Required | Default | Doc |
|---|---|---|---|
| data | no | NULL | A data frame, a file path (character string), or NULL. When NULL an interactive file chooser (file.choose()) opens. CSV (.csv) and tab-delimited (.tsv, .txt) files are supported when a path is supplied. |
| observation_id_col | yes |  | Character. Name of the column that holds the unique query identifier (e.g. "ESVId" for MiFish eDNA output). |
| score_col | yes |  | Character. Name of the column holding the raw match score (e.g. "PercMatch"). Values may be on any numeric scale; normalisation is performed later in TaxaLikely. |
| rank_system | no | NULL | Character vector of taxonomic rank column names, listed broadest to finest (e.g. c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")). Column matching is case-insensitive. When NULL (default), rank columns are auto-detected by matching column names against a built-in list of standard rank names (domain through form). |
| coverage_col | no | NULL | Character or NULL. Name of a column containing an alignment or detection quality fraction (0--1 or 0--100 scale, e.g. "qcovs" for BLAST query coverage). When supplied, the column is renamed to coverage in the canonical output. TaxaLikely's evaluate_likelihoods() accepts min_coverage to pre-filter candidates whose coverage falls below a threshold before likelihood calculation. Default NULL (no coverage column). |
| col_map | no | NULL | Optional named character vector of additional column renames applied before the core standardisation step, via TaxaTools::rename_cols(). Format: c("OldName" = "new_name"). Useful when source files use non-standard column names that are not auto-detected. |
| lowercase_names | no | TRUE | Logical. When TRUE (default), all column names in the output are converted to lowercase as the final step. This produces a fully consistent canonical object (e.g. kingdom, testid, accession) and avoids case-sensitivity surprises in downstream joins. Set to FALSE to preserve original column name casing. |

**Value:** A data frame with at minimum: 'observation_id' Unique query identifier (renamed from 'observation_id_col'). 'score_original' Raw match score (renamed from 'score_col'). Preserved unchanged throughout the pipeline; downstream functions add 'score_norm', 'score_softmax', and 'score_likelihood' columns as transformations are applied. 'taxon_name' Most specific non-NA taxon name (derived). 'taxon_name_rank' Rank of 'taxon_name', lowercase (derived). Useful for reporting what proportion of observations resolved to species/genus/family level, per eDNA minimum-information reporting guidelines (e.g. Thalinger et al. 2021). All other input columns are retained unchanged - *except* that when 'lowercase_names = TRUE' (the default), every column name in the output, including retained ones, is converted to lowercase; the underlying data is untouched, only the names.

#### Details

The result is a canonical match object ready for input to TaxaLikely. One row per observation_id x reference match (e.g. one ESV x one accession hit). Sample context (site, date, replicate) is stored in a separate table and joined to the likelihood output downstream -- it is not part of the match object.

### verify_removal_candidates(evaluation, ..., audit_max_hits = 100L, cache_dir = NULL, screen_corroborators = TRUE, verbose = TRUE)

Verify Removal Candidates Against a Wider Evidence Window

Re-evaluates ONLY the accessions an evaluation would actually remove, at a larger 'max_hits', and reports which of them stop being removable. Nothing is removed, nothing is written back to the production cache, and no verdict is overwritten - this is the pre-removal audit step, not a replacement for the screen.

| Param | Required | Default | Doc |
|---|---|---|---|
| evaluation | yes |  | An evaluate_reference_accessions() result. Needs accession plus either reference_action or the diagnostic columns score_reference_labels() derives it from. |
| ... | yes |  | Forwarded to evaluate_reference_accessions(). Must carry the production run's own verdict-affecting arguments (see above). |
| audit_max_hits | no | 100L | Integer (default 100L). The wider window. Note that on real data 13 of 34 accessions were still saturated at 100, so a clean result here bounds the problem rather than closing it. |
| cache_dir | no | NULL | Directory for the audit's own cache, or NULL (default) for no caching. Because max_hits is in params_key an audit can never overwrite a production row, but a separate directory keeps the production cache free of rows no production call will ever read. Also the cache screen_corroborators reads/writes corroborator verdicts through, so corroborators already evaluated (production or a prior audit) are served free. |
| screen_corroborators | no | TRUE | Logical (default TRUE). For a row spared on 1-2 corroborators (see the section below), also check those corroborators' OWN label via evaluate_reference_accessions() -- reusing an accession already present in evaluation for free where possible -- and surface a corroborator whose own reference_action is neither "keep" NOR "untested" (i.e. "caution"/"inspect"/ "remove") as a stronger, separate warning; an "untested" corroborator is deliberately NOT flagged -- no usable evidence about it is not evidence AGAINST it. Never un-spares a row automatically; a flagged corroborator is reported for a human to look at, not acted on. Requires cache_dir -- with cache_dir = NULL nothing is screened (zero extra NCBI calls) and corroborator_flagged is NA for every row, regardless of this parameter's value. FALSE also skips this entirely. |
| verbose | no | TRUE | Logical (default TRUE). |

**Value:** A data frame with one row per removal candidate: 'accession', 'listed_taxon', 'action_production'/'action_audit', 'anywhere_production'/'anywhere_audit', 'n_partners_production'/'n_partners_audit', 'n_hits_audit', 'still_saturated' (the audit itself hit 'audit_max_hits', so its own window is also truncated), 'spared' ('TRUE'/'FALSE', or 'NA' when the audit itself never completed - i.e. 'action_audit' is '"untested"'/'NA', e.g. an NCBI BLAST timeout or CPU-budget rejection. 'NA' is not "not removable" - test 'spared %in% TRUE', never bare 'spared', before treating a row as overturned). The corroborator columns - 'n_corroborators', 'best_corroborator_rank', 'corroborators' (a short list of the strongest partners that agreed), and, when 'screen_corroborators = TRUE', 'corroborator_accessions' (the checked accession(s)), 'corroborator_worst_action' (the worst 'reference_action' among them), and 'corroborator_flagged' (logical) - are ALWAYS present as columns, but are NA-filled whenever 'cache_dir' is 'NULL' (nothing to build them from) or a given row is not thin (spared on more than 2 corroborators, or not spared at all). Zero rows, and zero NCBI calls, when nothing would be removed; zero EXTRA NCBI calls (beyond the audit itself) when nothing is thin or 'screen_corroborators = FALSE'.

#### Why this exists

congruent_evidence_exists_anywhere is the hard veto that spares an accession from reference_action == "remove" however low its label_confidence. It is documented as walking the pool "not limited to top_n" -- and it is, but the pool is itself capped by max_hits (default 20). On the real PtConception 12S screen, 899 of 989 accessions (91%) came back AT that cap, so in practice "anywhere" has meant "anywhere in the top 20".

That was measured, not suspected (the veto_truncation_probe.R diagnostic (TaxaID_dev repository)): at max_hits = 100, congruent_evidence_exists_anywhere flipped FALSE to TRUE for 8 of 15 veto-critical accessions, and OQ846263 (Rathbunella hypoplecta) -- one of only two accessions that PtConception run would have removed -- turned out to be corroborated and dropped to "inspect". KM057967 (Jordania zonope) still removed at 100 hits, correctly: it is a genuine singleton. Both congruent controls were unchanged, as they must be, since widening a window cannot withdraw corroboration already observed.

Raising the max_hits DEFAULT was considered and deliberately not done: max_hits is part of params_key, so a change would invalidate every cached row across every project cache (~3,000 real rows) for a screen that has been NCBI-throttled before. Auditing only the removal candidates is the cheap targeted alternative -- a real population is 1-4 accessions, and removal is the one decision this package makes destructively.

#### Comparability, and why the params_key is checked

The audit is only meaningful if the re-evaluation differs from the production run in max_hits ALONE. Pass through ... exactly the same verdict-affecting arguments the production screen used -- barcode_term above all, since an untrimmed query is a different query. This function compares the params_key its own call will produce against the one carried on evaluation and warns, naming the fields, if anything other than max_hits differs. Heed that warning: a mismatch does not make the call fail, it makes the result mean nothing.

#### Read the corroborators, not just spared

congruent_evidence_exists_anywhere counts a corroborating partner without any notion of whether that partner's own label is trustworthy, so a mislabeled reference can be rescued by another instance of the SAME mislabel. This is not hypothetical -- it has happened in real use. GreatLakes KJ135626 (Pseudorasbora parva) came back spared = TRUE, rescued by exactly one partner agreeing at species rank: MZ605481, which this project's own the reference_accession_ground_truth.csv diagnostic (TaxaID_dev repository) records as a candidate_mislabel whose real identity is Cyprinus carpio. KJ135626's own best disagreeing hit is Cyprinus carpio at 100%. Two copies of one error agreeing with each other is not corroboration, and the LLM reviewer's independent "genuine_mislabel" call on that accession was the better answer.

refine_reference_verdicts() cannot close this: it discounts a partner by that partner's OWN verdict, and a corroborator which is merely a BLAST hit -- not itself in the screened population -- has no verdict to discount. Widening the window makes the exposure larger, not smaller, since it admits more potential bad corroborators. So treat spared as a prompt to look, not a conclusion: a row rescued by one or two partners gets an explicit warning naming them, and (screen_corroborators = TRUE) that corroborator's own label is checked -- never automatically, only flagged, per this project's own "flag, don't auto-act" convention.

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

