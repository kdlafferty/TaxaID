# Re-entry Prompt — Session 115
# Goal: Build/validate blast_sequences() → match object pipeline; evaluate shared NCBI fetcher

---

## What we want to accomplish

Build a working pathway from a list of query sequences (ESV sequences from DADA2 or a
FASTA file) to a TaxaMatch-compatible match object, suitable for input to
`TaxaLikely::evaluate_likelihoods()`.

The immediate entry point is `TaxaMatch::blast_sequences()`, which already exists in
`TaxaMatch/R/blast.R` as a Written (but untested in real use) function.

---

## Starting point: what already exists

### 1. `blast_sequences()` — TaxaMatch/R/blast.R

Signature:
```r
blast_sequences(seq_df,
                method = "remote",         # "remote" (NCBI URL API) or "local" (rBLAST)
                database = "nt",
                program = "blastn",
                score_range = 2,           # keep all hits within 2% of top hit
                max_hits = 20L,
                min_score = 70,
                min_query_coverage = 80,
                barcode_term = NULL,       # auto-detects barcode length range
                max_target_seqs = 100L,
                batch_size = 20L,
                email = NULL,              # required by NCBI policy
                ncbi_api_key = NULL,
                resolve_taxonomy = TRUE,   # resolve accessions → full lineage
                verbose = TRUE)
```

Input: data frame with `asv_id` and `sequence` columns (from `read_sequence_table()` /
`filter_sequences()`).

Returns: one row per query × hit with columns `observation_id`, `accession`, `score`
(percent identity 0-100), `evalue`, `bitscore`, `alignment_length`, `query_coverage`,
`subject_length`, plus taxonomy columns (kingdom…species) when `resolve_taxonomy = TRUE`.
Output is designed to feed directly into `standardize_match_data()`.

Internal helpers already in blast.R:
- `.blast_remote()` — NCBI BLAST URL API, batching, RID polling
- `.blast_local()` — local BLAST via rBLAST
- `.filter_blast_hits()` — score window algorithm
- `.parse_blast_xml()` — parse BLAST XML output
- `.resolve_taxonomy()` — NCBI taxid → full lineage via rentrez + xml2
- `.parse_taxonomy_xml()` — parse NCBI taxonomy XML
- `.resolve_taxonomy_from_accessions()` — accession-to-taxonomy bridge

### 2. Related sequence input functions — TaxaMatch/R/sequence_input.R

- `read_sequence_table()` — ingest DADA2 seqtab matrix, FASTA, or DNAStringSet
- `filter_sequences()` — filter by length range and min abundance

### 3. The full sequence pipeline workflow: `inst/workflow_fastq_to_match.R`

---

## Design question to address before writing new code

**Memory note (project_blast_ncbi_fetcher_todo.md):**

Three functions in TaxaLikely independently duplicate parts of the NCBI query pattern:
1. `fetch_reference_sequences()` — taxon + barcode_term → FASTA + taxonomy
2. `audit_barcode_coverage()` → internal `.reverse_barcode_check()` — genus-level
   nuccore search + batched entrez_summary
3. `blast_sequences()` → `.resolve_taxonomy()` — accession list → taxonomy

The question is whether to build a shared internal `.ncbi_fetch_records()` helper
(likely in TaxaLikely, since that's where the most NCBI work is) before adding more
NCBI query code, or whether the three use-cases are different enough to stay separate.

Key differences:
| Function | NCBI query direction | Input | Output needed |
|---|---|---|---|
| `fetch_reference_sequences()` | taxon → sequences | taxon name | FASTA + taxonomy |
| `audit_barcode_coverage()` | taxon → accession list → species | genus name | species count + accession list |
| `blast_sequences()` | query seq → accession hits + taxonomy | raw sequence | per-hit taxonomy |

The blast case is **reverse** (sequence → accession → taxonomy) while the other two
are **forward** (taxon name → NCBI). The taxonomy resolution step (accession → lineage)
is the shared piece. Whether that warrants a shared helper is an architectural
judgement call — discuss at session start.

---

## Match object interface (what blast_sequences must ultimately produce)

The canonical match object consumed by `TaxaLikely::evaluate_likelihoods()`:

| Column | Notes |
|---|---|
| `observation_id` | Unique query ID (ESVId, image hash, etc.) |
| `score_original` | Raw match score (PercMatch 0-100 for BLAST) |
| `taxon_name` | Best taxon label from `create_taxon_names()` |
| `taxon_name_rank` | Rank of taxon_name |
| `family`, `genus`, `species` | Must match `rank_system` |
| `accession` | Reference accession (optional but used by `infer_exclude_predicted()`) |

Note: `blast_sequences()` returns `score` (not `score_original`) — `standardize_match_data()`
handles this rename via `score_col` parameter.

---

## Suggested session approach

1. **Read `blast_sequences()` in full** — understand the current implementation state,
   identify any gaps or unimplemented stubs.

2. **Address the shared NCBI fetcher question** — decide whether `.ncbi_fetch_records()`
   is worth building now. If yes, sketch its signature. If no, proceed with
   `blast_sequences()` as-is.

3. **Test `blast_sequences()` on a small real example** — a handful of 18S or 12S ESV
   sequences from the PtConception dataset. Verify it returns the expected columns and
   feeds cleanly into `standardize_match_data()`.

4. **Wire up the full pipeline** in `inst/workflow_fastq_to_match.R`:
   ```r
   seq_df      <- read_sequence_table(...)
   seq_df      <- filter_sequences(seq_df, barcode_term = "18S")
   blast_hits  <- blast_sequences(seq_df, barcode_term = "18S", email = "...")
   match_obj   <- standardize_match_data(blast_hits, score_col = "score", ...)
   exclude_pred <- TaxaLikely::infer_exclude_predicted(match_obj)
   # → continue to audit_barcode_coverage(), evaluate_likelihoods(), etc.
   ```

---

## Key files to read at session start

- `TaxaMatch/R/blast.R` — full implementation
- `TaxaMatch/R/sequence_input.R` — read_sequence_table, filter_sequences
- `TaxaMatch/inst/workflow_fastq_to_match.R` — existing workflow script
- `TaxaLikely/R/fetch.R` lines 270-500 — fetch_reference_sequences() for comparison
  (shows the forward NCBI query pattern)

## Package state going in

- TaxaLikely: `infer_exclude_predicted()` just added (Session 114); `audit_barcode_coverage()`
  reverse-search rewrite (Session 113); both installed and clean
- TaxaFetch: `filter_gbif_quality()` gains `exclude_absent` (Session 114); installed and clean
- TaxaMatch: `blast_sequences()` written but not field-tested; `convert_taxonomy_backbone()`
  vectorized (Session 113); installed and clean
- All packages: `devtools::check()` passing (0 errors, 0 warnings) as of Session 114

## Install before starting

```r
.rs.restartR()
source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
.rs.restartR()
```
