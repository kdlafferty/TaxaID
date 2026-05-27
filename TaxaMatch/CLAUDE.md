# CLAUDE.md — TaxaMatch
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-26 (Session 88 — empty BirdNET file bug fix)

---

## Package Purpose
Stores and standardizes raw match data produced by external biological classification
programs (DNA barcoding pipelines, image classifiers, acoustic recognizers). Produces
a canonical match object for input to TaxaLikely.

Now also provides a complete FASTQ-to-match pipeline: ingest DADA2 sequence tables or
FASTA files, filter by length/abundance, BLAST against NCBI (remote or local), and
standardize results.

TaxaMatch does NOT perform score-to-likelihood conversion or reference quality checks —
those functions live in TaxaLikely.

**Status: All functions written and passing `devtools::check()` (0 errors, 0 warnings, 0 notes).**

---

## Dependency Chain

TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign
TaxaMatch → TaxaLikely → TaxaAssign

TaxaMatch depends on TaxaTools for `rename_cols()` and `create_taxon_names()`.
Also depends on `httr2` (remote BLAST API), `rentrez` + `xml2` (taxonomy resolution).
`Biostrings` and `rBLAST` are in Suggests (FASTA reading and local BLAST, respectively).

---

## Match Data Sources

| Source type | Example program | Score column | Sample ID column | Reference list |
|---|---|---|---|---|
| DNA barcoding | DADA2 + BLAST | `PercMatch` (0-100) | `ESVId` | NCBI nucleotide |
| Image classifier | Animl (MegaDetector + SpeciesNet) | `confidence` (0-1) | image_id / crop_id | SpeciesNet species list (~1,295 spp) |
| Acoustic recognizer | BirdNET | `confidence` (0-1) | recording_id × detection | BirdNET species list (~6,000+ spp) |

Raw column names vary by source — `standardize_match_data()` handles the rename.

### Image classifier details (Animl — PLANNED)

- **R package:** `animl` on CRAN (wraps Python backend; requires Python >= 3.12)
- **Pipeline:** `detect()` (MegaDetector bounding boxes) → `classify()` (species prediction) → `sequence_classification()` (temporal refinement)
- **Output:** CSV with species, confidence, bounding boxes; multi-level taxonomy fallback (species → genus → family when confidence is low)
- **Export formats:** CSV, COCO JSON, Timelapse CSV, folder organization
- **Score interpretation:** CNN confidence (0-1); NOT comparable to BLAST % identity — requires separate likelihood model calibration in TaxaLikely
- **Planned ingest function:** `read_animl_output()` — thin wrapper to read Animl CSV export into match object format
- **Reference:** https://docs.animl.camera/

### Acoustic recognizer details (BirdNET — PLANNED)

- **Tool:** BirdNET (Cornell Lab of Ornithology); CNN-based acoustic classifier
- **Output:** CSV with start_time, end_time, scientific_name, common_name, confidence (0-1); top-N candidates per detection
- **Score interpretation:** CNN confidence (0-1); same calibration caveat as image classifiers
- **Species coverage:** ~6,000+ bird species; species list is queryable (reference DB equivalent for completeness audits)
- **R interfaces:** BirdNET-R, warbleR (acoustic analysis), or direct Python CLI
- **Planned ingest function:** `read_birdnet_output()` — thin wrapper to read BirdNET CSV into match object format
- **Reference:** https://birdnet.cornell.edu/

### Design notes for non-sequence data types

1. **Ingest functions** (`read_animl_output()`, `read_birdnet_output()`) are thin — read CSV, apply `col_map`, pass to `standardize_match_data()`. No model fitting or classification happens in TaxaMatch.
2. **Score calibration** is fundamentally different from DNA: CNN confidence is not % identity. TaxaLikely's `train_likelihood_model()` handles this — it is score-agnostic and works on any 0-1 normalised score. But the training reference for image/acoustic data is the model's own species list, not NCBI sequences.
3. **Completeness audits** query the model's known species list (not NCBI). A new `audit_model_coverage()` function in TaxaLikely (or adapted `audit_reference_coverage()`) would compare expected species against the model's taxon list.
4. **Multi-level taxonomy fallback** (Animl reports genus when unsure of species) maps directly to `taxon_name_rank` — no architecture change needed.
5. **Priority:** Secondary to sequence pipeline. Placeholder stubs now; real implementation when test data (BirdNET CSV, Animl export) are available.

---

## Canonical Match Object (output of `standardize_match_data()`)

One row per `observation_id` × reference accession match.

| Column | Renamed from | Required | Notes |
|---|---|---|---|
| `observation_id` | `ESVId` (DNA) | Yes | Unique query identifier |
| `score` | `PercMatch` (DNA) | Yes | Raw match score |
| `taxon_name` | derived | Yes | Best taxon from `create_taxon_names()` |
| `taxon_name_rank` | derived | Yes | Rank of `taxon_name` |
| taxonomy cols | `Kingdom`…`Species` | Yes | Kept as-is from source |
| `TestId` | keep | No | Marker/barcode type; not renamed, not modelled |
| `Accession` | keep | No | Reference accession; not renamed, not modelled |

**Sample context** (site, date, replicate) is stored in a separate table and joined to
likelihood output downstream — it is NOT part of the match object.

---

## Function Inventory

### Sequence input and filtering

| Function | File | Status | Description |
|---|---|---|---|
| `read_sequence_table()` | R/sequence_input.R | Written | Ingest DADA2 seqtab matrix, FASTA file, or DNAStringSet; optional taxonomy join |
| `filter_sequences()` | R/sequence_input.R | Written | Filter ASVs by length range and minimum abundance; `barcode_term` auto-detection |

### BLAST search

| Function | File | Status | Description |
|---|---|---|---|
| `blast_sequences()` | R/blast.R | Written | Remote NCBI BLAST (httr2) or local rBLAST; score window filtering; taxonomy resolution |

### Image and acoustic input

| Function | File | Status | Description |
|---|---|---|---|
| `read_animl_output()` | R/read_image.R | Complete | Ingest Animl CSV export (MegaDetector + SpeciesNet); map confidence + taxonomy to match object. Accepts long format (default) or wide format via `n_candidates`. Configurable column names via `file_col`, `species_col`, `score_col`. `observation_id` = image filename stem. `min_confidence` and `top_n` filters. |
| `read_birdnet_output()` | R/read_acoustic.R | Complete | Ingest BirdNET-Analyzer CSV (detections × species × confidence); map to match object. Accepts file vector or directory path. `observation_id = "{file_stem}_{start_s}-{end_s}"`. `min_confidence` and `top_n` filters. |

### Standardization (original)

| Function | File | Status | Description |
|---|---|---|---|
| `standardize_match_data()` | R/standardize_match_data.R | Written | Rename columns, derive `taxon_name`, validate structure |
| `filter_redundant_hypotheses()` | R/standardize_match_data.R | Written | Drop higher-rank rows superseded by finer-rank rows within the same lineage and sample |

### Internal helpers

| Function | File | Description |
|---|---|---|
| `.resolve_taxonomy()` | R/blast.R | NCBI taxid to full lineage (kingdom-species) via rentrez + xml2 |
| `.parse_taxonomy_xml()` | R/blast.R | Parse NCBI taxonomy XML response |
| `.blast_remote()` | R/blast.R | Remote NCBI BLAST URL API with batching, rate limiting, RID polling |
| `.blast_local()` | R/blast.R | Local BLAST via rBLAST wrapper |
| `.filter_blast_hits()` | R/blast.R | Score window algorithm: min_score + query coverage + subject length + score_range + max_hits |
| `.parse_blast_xml()` | R/blast.R | Parse BLAST XML output into standardized hit data frame |
| `.resolve_taxonomy_from_accessions()` | R/blast.R | Accession-to-taxonomy bridge when taxids unavailable (XML format) |
| *(removed — Session 57)* | R/sequence_input.R, R/blast.R | `.barcode_length_defaults` and `.resolve_barcode_lengths_local()` moved to TaxaTools; now `TaxaTools::resolve_barcode_lengths()` |
| `.parse_semicolon_headers()` | R/sequence_input.R | Parse FASTA headers: accession;kingdom;...;species |

---

## Workflow Scripts

| File | Purpose |
|---|---|
| `inst/workflow_standardize.R` | Original: load match data, standardize, filter redundant |
| `inst/workflow_fastq_to_match.R` | FASTQ-to-match pipeline: DADA2 output, filter, BLAST, standardize |

---

## Score Window Algorithm (blast_sequences)

Rather than a flat top-N cutoff, `blast_sequences()` filters per query:
1. Remove hits below `min_score` (default 70%)
2. Remove hits with query coverage below `min_query_coverage` (default 80%)
3. Remove hits with subject length outside barcode range (via `barcode_term`)
4. Per query: keep all hits within `score_range` of the top hit (default 2%)
5. Apply `max_hits` safety cap per query (default 20)

A clear top match may return only 1-3 hits. An ambiguous query retains all
plausible candidates.

---

## Barcode Length Defaults

**Session 57 (Prompt 16):** Local copies of `.barcode_length_defaults` and
`.resolve_barcode_lengths_local()` removed from `R/sequence_input.R` and `R/blast.R`.
Now uses `TaxaTools::barcode_length_defaults` and `TaxaTools::resolve_barcode_lengths()`
(single source of truth). See TaxaTools CLAUDE.md for the full barcode length table.

---

## `filter_redundant_hypotheses()`

**Purpose:** When a match pipeline returns both species-level and genus-level hits for the
same sample, the genus-level row is redundant — it adds no information that the species
row doesn't already provide, and it inflates the taxon list sent to TaxaLikely / TaxaAssign.
This function removes such redundant higher-rank rows while retaining genus/family rows
for lineages that have NO species-level match.

**Critical design point — redundancy is lineage-local, not global:**
A genus-level row for *Gobius* is redundant only if a *Gobius* species row also appears
for the same `observation_id`. It is NOT redundant merely because some other species-level row
(e.g., *Acanthogobius flavimanus*) exists in the same sample. Dropping all genus rows
whenever any species match exists would silently discard real alternative hypotheses.

**Algorithm:**

1. Convert `taxon_name_rank` to a numeric rank score using the supplied `rank_system`
   vector (e.g., `c("kingdom","phylum","class","order","family","genus","species")`).
   Position in vector = score; species = highest, kingdom = lowest.

2. For each `observation_id × row`, determine whether any other row in the same `observation_id`
   satisfies BOTH:
   - Its rank score is strictly higher (finer rank), AND
   - It shares the same values in ALL taxonomy columns that correspond to ranks coarser
     than or equal to the current row's rank.
   (This checks "is this row an ancestor of any finer-rank row?")

3. Drop rows for which step 2 is TRUE.

**No score column required** — the only ordering information needed is the rank ordering
vector and the taxonomy columns (kingdom → species). The DNA/image/acoustic match score
is irrelevant to this filter.

**Input requirements:**
- `match_df` with `observation_id`, `taxon_name_rank`, and the full set of taxonomy columns
  named in `rank_system` (populated down to the matched rank; finer ranks are NA).
- `rank_system`: character vector, coarsest first (e.g., `kpcofgs`).
  Rows with `taxon_name_rank` not found in `rank_system` are retained unchanged with a
  warning.

**Signature (proposed):**
```r
filter_redundant_hypotheses <- function(match_df,
                                         rank_system = c("kingdom","phylum","class",
                                                        "order","family","genus","species"))
```

**Example:** sample S1 has rows for *Gobius paganellus* (species), *Gobius* sp. (genus),
and *Acanthogobius* sp. (genus). The *Gobius* genus row is dropped (superseded by
*G. paganellus*). The *Acanthogobius* genus row is retained (no species match for that
lineage).

**Where to call it:** Inside `standardize_match_data()` as an optional step, or as a
standalone exported function called explicitly. Recommend standalone so callers can
inspect before and after. Should run AFTER `create_taxon_names()` so `taxon_name_rank`
is already populated.

**Note for implementation:** The prototype `f_filter_redundant_higher_hypotheses()` in
`TaxaAssign/inst/TaxaAssign_llm_workflow.R` (Session 36) uses a score-column approach
that conflates rank ordering with match quality and applies a global (not lineage-local)
filter. The rewrite described here supersedes it. The `f_score_ordinal_col()` helper in
the same workflow file has been removed (Session 39); rank scoring is now handled inline
inside `filter_redundant_hypotheses()` via `match()`.

---

## Key Design Notes

- Column renaming uses `TaxaTools::rename_cols()` with a source-specific `col_map`
- Taxonomic name derivation uses `TaxaTools::create_taxon_names()`
- Output must conform exactly to the match object spec above before passing to TaxaLikely
- `TestId` (marker type) and `Accession` (reference accession) are retained but not
  renamed and play no role in the likelihood model

---

## Session Notes

**Session 27 (2026-03-26)**
- Package scaffold created; all functions planned but not written

**Session 30 (2026-03-27)**
- Scope revised: all modeling and reference QC functions moved to new package TaxaLikely
- TaxaMatch is now a thin shell for raw data standardization only
- DESCRIPTION updated to reflect new scope
- Match object spec confirmed from MiFish eDNA example data

**Session 39 (2026-03-31)**
- `filter_redundant_hypotheses()` implemented in `R/standardize_match_data.R`
- Lineage-local algorithm: genus row dropped only when a finer-rank row from the same lineage exists in the same `observation_id`; rows with unknown ranks retained with warning
- 13 tests added in `tests/testthat/test-filter_redundant_hypotheses.R`; `devtools::check()` passes (0 errors, 0 warnings)
- `inst/workflow_standardize.R` updated with before/after filter step
- `TaxaAssign/inst/TaxaAssign_llm_workflow.R` updated: placeholder `f_filter_redundant_higher_hypotheses()` and `f_score_ordinal_col()` removed; replaced with `TaxaMatch::filter_redundant_hypotheses()`

**Session 53 (2026-04-10)**
- FASTQ-to-match pipeline implemented: 3 new exported functions + 9 internal helpers
- `read_sequence_table()`: ingests DADA2 sequence table (matrix), FASTA files (via Biostrings), or DNAStringSet objects; optional taxonomy join by sequence or accession; semicolon-delimited header parsing
- `filter_sequences()`: length range + minimum abundance filtering; `barcode_term` auto-detection from `.barcode_length_defaults` lookup (duplicated from TaxaLikely)
- `blast_sequences()`: remote NCBI BLAST (httr2-based URL API with batching, rate limiting, RID polling, exponential backoff) or local BLAST (rBLAST wrapper); score window algorithm replaces flat top-N (keep hits within `score_range`% of top hit per query); subject length filtering via barcode_term; taxonomy resolution via rentrez + xml2
- `.resolve_taxonomy()`: batched NCBI taxonomy XML fetch + parse; same pattern as TaxaLikely's `.fetch_taxonomy_map()`
- New dependencies: httr2, rentrez, xml2 (Imports); Biostrings, rBLAST (Suggests)
- `inst/workflow_fastq_to_match.R`: end-to-end workflow with DADA2 prerequisite, local BLAST setup instructions
- `devtools::check()`: 0 errors, 0 warnings, 0 notes; 125 tests passing

**Session 54 (2026-04-11)**
- Remote BLAST debugged and working end-to-end on real Palmyra eDNA data (75 ESVs, 419 hits)
- Three bugs fixed in BLAST URL API integration:
  1. Submit: removed FORMAT_TYPE/FORMAT_OBJECT/ALIGNMENT_VIEW from PUT request (NCBI ignores format params at submission time)
  2. Poll: split into status-check (FORMAT_OBJECT=SearchInfo) then result-retrieval (FORMAT_TYPE=XML); fixed sprintf `%d` crash when `elapsed` became non-integer double after backoff
  3. Retrieval: switched from FORMAT_TYPE=Tabular (NCBI returned empty status page) to FORMAT_TYPE=XML (reliable, used by BioPython)
- `.parse_blast_tabular()` replaced by `.parse_blast_xml()`: parses BLAST XML Iteration/Hit/Hsp structure; extracts pident, qcovs, slen, evalue, bitscore
- `.resolve_taxonomy_from_accessions()` added: accession-to-taxid bridge via rentrez entrez_search + entrez_summary, then taxid-to-lineage via existing `.resolve_taxonomy()`; needed because BLAST XML doesn't include taxids directly
- Filtering defaults confirmed appropriate for TaxaLikely pipeline: min_score=70, min_query_coverage=80, score_range=2 are intentionally permissive; downstream TaxaLikely model handles discrimination; taxonomic filtering (e.g., keep only Chordata) belongs in workflow, not in blast_sequences()
- `devtools::check()`: 0 errors, 0 warnings, 1 note (stray seqtab_nochim.rds)

**Session 55 (2026-04-12)**
- Design discussion: extending TaxaMatch to image and acoustic data sources
- **Animl** (camera trap images): R package on CRAN; MegaDetector detection → SpeciesNet classification; CSV export with species + confidence (0-1); ~1,295 species; multi-level taxonomy fallback (species → genus → family). Planned: `read_animl_output()`
- **BirdNET** (acoustic): Cornell Lab CNN; CSV output with scientific_name + confidence (0-1); top-N candidates per detection; ~6,000+ bird species with queryable species list. Planned: `read_birdnet_output()`
- Match Data Sources table updated with all three data types
- Detailed design notes added for non-sequence data types: score calibration differences, completeness audit approach, taxonomy fallback mapping
- Function inventory updated with planned `read_animl_output()` and `read_birdnet_output()`
- Priority: secondary to sequence pipeline polishing; implement when test data available

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename across all R source, tests, vignettes, inst/, README
- `sample_id_col` param → `observation_id_col` in `standardize_match_data()`
- `globalVariables("sample_id")` → `globalVariables("observation_id")`
- 166 tests passing; `devtools::check()` clean after reinstall

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaMatch-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 87 (2026-05-26)**
- `read_birdnet_output()` implemented in `R/read_acoustic.R` (was Planned since Session 55).
  Reads BirdNET-Analyzer CSV output (one file per recording). Accepts file vector or directory.
  `observation_id = "{file_stem}_{start_s}-{end_s}"`. `score` = Confidence (0-1). `genus` derived
  from first word of Scientific name. `min_confidence` and `top_n` filters. `source_file` column
  for ground-truth join back to Xeno-canto reference metadata.
  Internal helper `.parse_birdnet_file()` validates required BirdNET columns.
- 9 offline tests in `tests/testthat/test-read_acoustic.R` (synthetic `tempfile()` + `write.csv()`
  BirdNET data — no real recordings needed).
- `devtools::check()`: 0 errors, 0 notes (2 pre-existing vignette warnings).

**Session 88 (2026-05-26)**
- Bug fix: `.parse_birdnet_file()` crashed with `"arguments imply differing number of rows: 1, 0"`
  when a BirdNET CSV contained only a header row and no detections (e.g., BirdNET found nothing
  above the confidence threshold in a short or quiet recording). Root cause: `source_file = basename(f)`
  has length 1 but all other columns (`start_vals`, `end_vals`, etc.) are `numeric(0)` / `character(0)`.
  Fix: added early return for `nrow(df) == 0L` that produces a correctly typed 0-row data frame
  and emits an informational message naming the empty file.
- 2 new tests in `test-read_acoustic.R` (total now 11): empty CSV returns 0-row data frame with
  correct columns; mix of empty + non-empty files returns only rows from non-empty file.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.
