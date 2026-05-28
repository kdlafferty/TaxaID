# CLAUDE.md -- TaxaLikely
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-28 (Session 94 -- write_reference_fasta, build_site_reference)

---

## Package Purpose
Converts match scores (DNA percent identity, image similarity, acoustic scores) into
likelihoods for taxonomic assignment. Takes a standardized match object (from TaxaMatch
or user-supplied) and produces per-hypothesis `likelihood_point_est`, `likelihood_mean`,
`likelihood_sd` columns required by TaxaAssign.

Also provides reference database quality tools:
- Detecting mislabeled reference sequences
- Auditing taxonomic completeness (identifying unreferenced taxa missing from the reference)

Part of the TaxaID ecosystem. Depends on TaxaTools for name cleaning and column standardization.

**Status: All functions written and passing devtools::check() (0 errors, 0 warnings, 0 notes).**
**Source refactored from: `~/Rscripts/eDNA/Bayesian  Workflow/Universal_Biological_Classifier_Working_2.R`**

---

## Dependency Chain

TaxaTools -> TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign / TaxaMatch -> **TaxaLikely** -> TaxaAssign

TaxaLikely depends on TaxaTools for:
- `create_taxon_names()` -- derives `taxon_name` + `taxon_name_rank` (used in evaluate.R for H2/H3 rows)

---

## Match Object Interface (Input)

The canonical match object produced by `standardize_match_data()` (TaxaMatch) or
supplied directly by the user. One row per `observation_id` x reference accession match.

| Column | Type | Required | Notes |
|---|---|---|---|
| `observation_id` | character | Yes | Unique query ID (e.g. ESVId, image hash, clip ID) |
| `score` | numeric | Yes | Raw match score (e.g. PercMatch 0-100, or similarity 0-1) |
| `taxon_name` | character | Yes | Best taxon label for this reference (from `create_taxon_names()`) |
| `taxon_name_rank` | character | Yes | Rank of `taxon_name` (e.g. "species", "genus") |
| taxonomy cols | character | Yes | e.g. `family`, `genus`, `species` -- must match `rank_system` |
| `testid` | character | No | Marker/barcode type (e.g. "MiFishU") -- retained, not modelled |
| `accession` | character | No | Reference accession -- retained, not modelled |

**Note:** Sample context (site, date, replicate) lives in a separate table and is joined
to likelihood output downstream -- it is NOT part of the match object.

---

## Likelihood Object Interface (Output -> TaxaAssign)

`evaluate_likelihoods()` returns a **named list** with two components:

**`$likelihoods`** -- one row per `observation_id` x taxon hypothesis; pass to
`filter_top_hypotheses()`, `apply_coverage_constraints()`, and
`TaxaAssign::compute_posterior()`.

| Column | Type | Description |
|---|---|---|
| `observation_id` | character | Query identifier |
| `taxon_name` | character | Hypothesized taxon (never NA) |
| `taxon_name_rank` | character | Rank of hypothesis |
| `hypothesis_type` | character | "specific_candidate", "unreferenced_species", "unreferenced_genus" |
| `likelihood_point_est` | numeric | Point estimate (deterministic) |
| `likelihood_mean` | numeric | Mean across Monte Carlo simulations |
| `likelihood_sd` | numeric | SD across simulations (0 if n_sims = 0) |

**`$unresolved`** -- rows from the original `match_df` for any `observation_id` that
produced no usable likelihoods (e.g., all candidates matched only at a rank
coarser than `rank_system` specifies). Empty data frame if none. Re-run
`evaluate_likelihoods()` on `$unresolved` with a coarser `rank_system`.

TaxaAssign joins on `taxon_name` + `taxon_name_rank`. TaxaExpect provides priors
for `unreferenced_species` and `unreferenced_genus` rows (unreferenced species priors).

---

## Function Inventory

### Reference acquisition (build reference_df)

| Function | File | Status | Description |
|---|---|---|---|
| `fetch_reference_sequences()` | `R/fetch.R` | Written | Search NCBI by taxon + barcode marker, resolve taxonomy via taxid bridge, filter/downsample, download FASTA → `reference_df`. Count-first estimation; resumable via `cache_dir` (default `tempdir()`). Per-taxon tryCatch: NCBI rate-limit errors skip one taxon with warning instead of crashing the entire run. |
| `read_crabs_output()` | `R/read_crabs.R` | Written | Read CRABS internal-format database (headerless 11-column TSV) → `reference_df`. Params: `rank_system` (NULL = auto-detect from populated columns), `max_n_bases`, `require_species` (uses `TaxaTools::is_valid_species_name()`), `dereplicate` (collapse exact-duplicate seqs within species). Complementary to `flag_reference_errors()`: CRABS handles bulk QC; TaxaLikely catches mislabeling CRABS cannot detect. |
| `read_reference_fasta()` | `R/fetch.R` | Written | Read local FASTA + taxonomy → `reference_df`. For CRUX, GenBank dumps, custom databases. `taxonomy` param accepts a data frame; new `taxonomy_file` param accepts a 2-column TSV (QIIME2/RESCRIPt/SILVA/MIDORI2 prefix-style `k__Kingdom;...` or positional `Kingdom;...`). Exactly one of `taxonomy` or `taxonomy_file` must be supplied (previously `taxonomy` was required). Internals: `.parse_taxonomy_tsv()`, `.parse_tax_string()`. |
| `fetch_reference_recordings()` | `R/fetch_recordings.R` | Written | Fetch bird sound recordings from Xeno-canto API v3. Returns metadata table for acoustic reference training. `api_key` required (read from `XC_API_KEY` env var). `quality` A-E filter; `max_per_species` cap; optional `download = TRUE`. Internals: `.xc_query_all()`, `.xc_standardize_cols()`, `.parse_xc_duration()`. |

### Training (fit model on reference database)

| Function | File | Status | Description |
|---|---|---|---|
| `build_sequence_matrix()` | `R/build_sequence.R` | Written | Align DNA sequences (DECIPHER), compute pairwise distance matrix → pair format for `train_likelihood_model()`. Output now includes `coverage` column (positions where both sequences are non-gap / shorter unaligned length). Renamed from `build_reference_matrix()` Session 88. |
| `build_acoustic_reference()` | `R/build_acoustic.R` | Written | Acoustic analog of `build_sequence_matrix()`. Joins BirdNET detections to Xeno-canto ground truth; labels H1/H2/H3; maps `type` → `testid`. Output now includes `coverage` column (Xeno-canto quality grade mapped A→1.0, B→0.8, C→0.5, D→0.3, E→0.1). Returns same `.x`/`.y` pair format. Train one model per `testid` type (song, call) as eDNA trains per marker. |
| `build_image_reference()` | `R/build_image.R` | Written | Image analog of `build_acoustic_reference()`. Joins any image classifier output (Animl, iNaturalist CV, SpeciesNet) to user-supplied ground-truth image labels; labels H1/H2/H3; `testid` from `images_meta$testid`. `coverage` sourced from `image_df$coverage` (bbox area) or `images_meta$quality`. Join key: `observation_id` (image file stem) matches `file_path_sans_ext(basename(image_path))`. Train one model per testid (image type / classifier). |
| `flag_reference_errors()` | `R/train.R` | Written | Flag mislabeled references |
| `train_likelihood_model()` | `R/train.R` | Written | Full training pipeline -> `taxa_model_params` object; `anchor_perfect` param (default TRUE) injects synthetic perfect-match observations |

### Inference (apply model to query observations)

| Function | File | Status | Description |
|---|---|---|---|
| `evaluate_likelihoods()` | `R/evaluate.R` | Written | Apply model to all queries; outputs likelihood object. `verbose` param (default FALSE) logs species-specific param fallback. |
| `filter_top_hypotheses()` | `R/evaluate.R` | Written | Keep finest-rank candidates per query |

### Reference coverage

| Function | File | Status | Description |
|---|---|---|---|
| `audit_barcode_coverage()` | `R/coverage.R` | Written *(planned deprecation)* | **Preferred for eDNA/barcode data.** Unreferenced = described species with NO barcode sequence (cannot appear as reference match). Per-species `retmax=0` NCBI nucleotide count queries; taxonomy-first species list. Census: `in_reference`, `has_seqs_not_in_ref`, `unreferenced`, `is_complete`. Params: `barcode_term` (vector ok), `max_date`, `min_len`, `max_len`, `species_list`. **Slow for species-rich genera** -- will be superseded by `suggest_unreferenced_species()` (LLM-first). |
| `audit_reference_coverage()` | `R/coverage.R` | Written | Queries NCBI taxonomy tree (all described species). Use for non-barcode libraries (images, sounds) where barcode availability is irrelevant. |
| `audit_acoustic_coverage()` | `R/coverage.R` | Written | **Acoustic/image.** Which plausible species are absent from classifier's known list? Simple set-membership check — no NCBI API. `match_df` param annotates in_match_data. Returns `list(census, unreferenced)` matching `audit_barcode_coverage()` format. |
| `apply_coverage_constraints()` | `R/coverage.R` | Written | Suppress "unreferenced_species" for fully-sampled genera |
| `expand_unreferenced_hypotheses()` | moved to TaxaAssign | — | Requires both TaxaLikely and TaxaExpect outputs; belongs at the convergence point. See `TaxaAssign/R/expand_unreferenced.R`. |

### Coverage quality calibration

| Function | File | Status | Description |
|---|---|---|---|
| `calibrate_coverage_filter()` | `R/calibrate.R` | Written | Sweep a grid of coverage thresholds over `build_sequence_matrix()` or `build_acoustic_reference()` output; return per-threshold breadth + H1/H2 discrimination metrics. Key columns: `breadth`, `h1_retention`, `h2_retention`, `youden_j` (primary — maximised at Pareto-optimal threshold), `discrimination` (ratio form), `mean_h1_score`. Detects categorical coverage (≤10 unique values, e.g. acoustic grades) and messages that J will be near-flat. Auto-detects finest rank from `.x`/`.y` column pairs via `.detect_finest_rank_col()`. |
| `coverage_threshold()` | `R/calibrate.R` | Written | Quantile-based shortcut: returns the coverage value at the `(1 − keep_frac)` quantile so that `keep_frac` of pairs are retained (default 0.95). For categorical coverage, snaps to the nearest unique value with a message showing the achieved retention fraction. |

### Match object cleaning and export

| Function | File | Status | Description |
|---|---|---|---|
| `remove_flagged_references()` | `R/clean.R` | Written | Remove mislabeled accessions from match_df using `flag_reference_errors()` output. Handles version suffix stripping. `remove_unverified_singletons` param (default FALSE). |
| `write_reference_fasta()` | `R/write_fasta.R` | Written | Export `reference_df` to FASTA + optional companion taxonomy TSV. FASTA header: `>{composite_id} {rank vals}` (NA ranks omitted). TSV is positional format compatible with `read_reference_fasta(taxonomy_file=)`. `rank_system` auto-detected when NULL. |
| `build_site_reference()` | `R/build_site_reference.R` | Written | High-level site-specific reference builder (DNA only). taxa list → `fetch_reference_sequences()` → optional `flag_reference_errors()` → `audit_barcode_coverage()` → `write_reference_fasta()`. Returns `list($reference_df, $errors, $census, $unreferenced)`. `output_dir` param writes `reference.fasta` + `reference_taxonomy.tsv`. |

### Diagnostics

| Function | File | Status | Description |
|---|---|---|---|
| `interpret_model()` | `R/interpret.R` | Written | Summarise trained model: expected match %, gap, per-species profiles |

### Reporting

| Function | File | Status | Description |
|---|---|---|---|
| `report_likelihood()` | `R/report_likelihood.R` | Written | Generate `report_section` summarizing model training (n_species, AIC, anchoring, mislabel detection). For `assemble_report()`. |

### Internal helpers (not exported)

| Function | File | Description |
|---|---|---|
| `.normalize_scores()` | `R/normalize.R` | Normalise raw scores to (0,1); clip for logit |
| `.prep_training_data()` | `R/train.R` | Logit-transform, compute within-species pairs + gap |
| `.evaluate_one_query()` | `R/evaluate.R` | Per-query H1/H2/H3 likelihood calculation |
| `.detect_finest_rank_col()` | `R/calibrate.R` | Auto-detect finest rank from paired `.x`/`.y` columns using `TaxaTools::standard_ranks`; used by `calibrate_coverage_filter()` |
| `.build_search_term()` | `R/fetch.R` | Construct NCBI nucleotide search query from taxon + barcode_term + dates |
| `.fetch_summaries_batched()` | `R/fetch.R` | Batched NCBI summary retrieval (accession, taxid, length); exponential backoff |
| `.fetch_taxonomy_map()` | `R/fetch.R` | Batched NCBI taxonomy XML → full lineage lookup table |
| `.fetch_fasta_batched()` | `R/fetch.R` | Batched FASTA download from NCBI nucleotide |
| `.parse_fasta_text()` | `R/fetch.R` | Parse FASTA text into data.frame(composite_id, sequence) |
| `.parse_taxonomy_tsv()` | `R/fetch.R` | Parse 2-column taxonomy TSV (QIIME2/RESCRIPt/SILVA/MIDORI2) → data frame for `read_reference_fasta(taxonomy_file=)`. Skips header rows; calls `.parse_tax_string()` on unique strings only (efficient for large files). |
| `.parse_tax_string()` | `R/fetch.R` | Parse one semicolon-delimited taxonomy string; auto-detects prefix-style (`k__`, `d__`, etc.) vs positional format; maps to user-supplied `rank_system`. |
| `.crabs_std_hierarchy` | `R/fetch.R` | Character constant: standard 7-level CRABS/NCBI rank order used for positional taxonomy-string parsing. |

---

## Workflow Scripts

Six self-contained workflow scripts in `inst/workflows/`, replacing the old
monolithic `inst/TaxaLikely_workflow.R` (retained for reference but superseded).

| # | File | Purpose | Key functions |
|---|---|---|---|
| 1 | `1_fetch_references_workflow.R` | Build `reference_df` from NCBI or local FASTA | `fetch_reference_sequences()`, `read_reference_fasta()` |
| 2 | `2_flag_errors_workflow.R` | Find mislabeled references; explore/tabulate/report | `build_sequence_matrix()` → `flag_reference_errors()` |
| 3 | `3_train_model_workflow.R` | Train likelihood model from DNA reference matrix | `build_sequence_matrix()` → `train_likelihood_model()` → `interpret_model()` |
| 3b | `3b_acoustic_reference_workflow.R` | **Acoustic:** Xeno-canto → BirdNET → train one model per recording type | `fetch_reference_recordings()` → BirdNET (Python) → `read_birdnet_output()` → `build_acoustic_reference()` → `train_likelihood_model()` |
| 3c | `3c_image_reference_workflow.R` | **Image:** labeled reference images → Animl/SpeciesNet → train one model per image type | user-supplied `images_meta` → classifier (R/Python) → `read_animl_output()` → `build_image_reference()` → `train_likelihood_model()` |
| 4 | `4_score_to_likelihood_workflow.R` | Convert match scores to likelihoods for TaxaAssign | `evaluate_likelihoods()` → `filter_top_hypotheses()` |
| 5 | `5_audit_coverage_workflow.R` | Audit reference completeness; constrain likelihoods | `audit_barcode_coverage()` / `audit_reference_coverage()` → `apply_coverage_constraints()` |

Workflows 2 and 3 share `build_sequence_matrix()` — build once, reuse.
Workflow 3b is the acoustic analog: Xeno-canto recordings replace NCBI sequences;
`build_acoustic_reference()` replaces `build_sequence_matrix()`. Train one model
per recording type (song, call) exactly as DNA trains one model per barcode marker.
Workflow 4 includes a one-liner to remove flagged errors from the match object
before evaluating likelihoods (no dedicated function needed).

### Other inst/ files

| File | Purpose |
|---|---|
| `inst/plot_likelihood_landscape.R` | Standalone two-panel visualization of H1/H2 density surfaces with example points (A/B/U). For presentations and manuscripts; not an exported function. |
| `inst/TaxaLikely_supplemental_methods.md` | Statistical methods background document adapted from early design docs; 10 sections covering the generative Bayesian framework, feature engineering, hypotheses, anchoring, and visualization. Future manuscript seed. |

---

## `model_params` Object (class `"taxa_model_params"`)

Output of `train_likelihood_model()`.

| Slot | Type | Description |
|---|---|---|
| `H1_Lookup` | data.frame | Per-species `lookup_key`, `rank`, `mu_score`, `mu_gap`, `sigma_score` (shrunk) |
| `H1_Global_Mu` | named numeric | Global fallback mean: `score_logit`, `gap_logit` |
| `H1_Sigma` | 2x2 matrix | Global covariance (dimnames: `score_logit`, `gap_logit`) |
| `H2` | list | Missing-species params: `delta` (logit offset from H1 mean), `sigma` (2x2 matrix) |
| `H3` | list | Missing-genus params: `delta`, `sigma` (2x2 matrix) |
| `Stats` | list | Diagnostics: `AIC_Score`, `n_species`, `n_singletons`, `n_anchors` |
| `reference_errors` | data.frame | Output of `flag_reference_errors()` (mislabeled + singleton flags). Use with `remove_flagged_references()` to clean match objects. Auto-used by `run_bayesian_pipeline()`. |

---

## Critical Design Decisions (Session 31)

### rank_system convention
**Always coarse-to-fine** (e.g., `c("family", "genus", "species")`).
The last element (finest rank) maps to `rank_code_a` internally.
This matches the order of taxonomy columns in the match object.

### p_match scale
`build_sequence_matrix()` outputs `p_match = 1 - distance` where distance is
from DECIPHER (0-1 scale). All downstream functions (`flag_reference_errors()`,
`.prep_training_data()`) expect **p_match on 0-1 scale**.
The `score` column in the match object (input to `evaluate_likelihoods()`) can
be on either 0-1 or 0-100 scale -- `.normalize_scores()` auto-detects.

### H2/H3 sigma slots
Both `H2$sigma` and `H3$sigma` are **2x2 matrices** (not scalars) with
dimnames `c("score_logit", "gap_logit")`. This matches the `dmvnorm()` call
signature in `.evaluate_one_query()`.

### H2/H3 filtering
H2 and H3 hypotheses CAN be filtered out by `ratio_threshold` when scores
are high (the missing-taxon distribution is far from the observed scores).
This is correct behavior -- TaxaAssign treats absent rows as likelihood = 0.
Use `ratio_threshold = 0` to always retain all three hypothesis types.

### Rank generalization
`f_generalize_taxonomy_ranks()` from UBC is implemented inline in
`.prep_training_data()` as `.generalize_ranks()`. Not exported.
`f_ungeneralize_taxonomy_ranks()` from UBC is **dead code** -- never
used in the original source. Dropped entirely.

### TaxaTools::create_taxon_names() usage
Called inside `.evaluate_one_query()` to derive `taxon_name` + `taxon_name_rank`
for H2/H3 rows (where finest rank(s) are set to NA before calling).
Must be installed; it is in Imports.

---

## Statistical Design Notes

- **Score metric:** any raw match score; normalised to (0,1) then logit-transformed
- **Gap metric:** best-match logit score minus second-best logit score -- key discriminator
- **H1 (Known Species):** 2D multivariate normal in (score_logit, gap_logit); species-specific
  params with Empirical Bayes shrinkage toward global mean
- **H2 (Missing Species):** same distribution shifted left by `H2$delta` -- score expected ~3
  logit units below H1 mean (sister species). Delta computed from observed foreign-match
  distribution in training data (default 3.0 if insufficient data).
- **H3 (Missing Genus):** shifted further left by `H3$delta` = `H2$delta + 2.0`
- **Singleton queries:** 1D normal (score only) when only one candidate taxon
- **Pseudo-data anchoring:** `anchor_perfect = TRUE` (default) injects synthetic
  perfect-match rows (score = logit(1-ε), gap = 95th percentile of real positive gaps)
  into training data. Prevents the "perfection penalty" where a 100% match scores lower
  than a 99% match because the model has never seen a perfect score. Anchors are excluded
  from H1_Lookup (no per-species parameters for "ANCHOR_PERFECT"). Count = max(5, 10% of data).
- **Shrinkage:** `w = N / (N + prior_weight)`; per-species variance + gap mean shrunk
  toward global. Default `prior_weight = 10.0`.
- **Monte Carlo:** n_sims samples from score distribution -> `likelihood_mean` + `likelihood_sd`
- **Median-across-references** approach: `evaluate_likelihoods()` takes max score per taxon_name,
  summarising across multiple accessions before likelihood calculation.

---

## Known Footguns

### TaxaTools::create_taxon_names() must be installed
`evaluate_likelihoods()` calls `TaxaTools::create_taxon_names()`. If TaxaTools
is not installed (e.g., in test environments), tests that call `evaluate_likelihoods()`
will fail. Guard with `skip_if_not_installed("TaxaTools")`.

### build_sequence_matrix() needs DECIPHER + Biostrings (Suggests)
These are Bioconductor packages. Install with `BiocManager::install("DECIPHER")`.
They are in Suggests, not Imports -- not loaded at package startup.
The function checks for them at runtime.

### lme4 hierarchy fitting with small data
`train_likelihood_model(use_hierarchy = TRUE)` requires enough taxonomic levels
(>= 2 rank columns in training data) and sufficient variance across ranks for
lme4 to converge. Falls back gracefully to global mean with a message.

### expand_unreferenced_hypotheses() workflow order
`expand_unreferenced_hypotheses()` must run **before** `apply_coverage_constraints()`.
Coverage constraints operate on `hypothesis_type` and `taxon_name`; if constraints are
applied first (zeroing the generic H2 row), expansion will produce named rows with
non-zero likelihoods that bypass the constraint. Correct order:
`evaluate_likelihoods()` → `filter_top_hypotheses()` → `expand_unreferenced_hypotheses()`
→ `apply_coverage_constraints()`.

---

## Session Notes

Sessions 30–88 archived in `ecosystem_docs/session_notes/TaxaLikely_sessions.md`.

**Session 90 (2026-05-27)**
- `coverage` column added to `build_sequence_matrix()` output. Computed as the number of
  MSA positions where both sequences are non-gap, divided by the shorter unaligned sequence
  length. Pre-computes per-sequence gap masks once (O(n × alignment_width)) before looping
  over sparse pairs. Documented in `@return`.
- `coverage` column added to `build_acoustic_reference()` output. Derived from
  `recordings_meta$quality`: A→1.0, B→0.8, C→0.5, D→0.3, E→0.1. Placed on the same [0,1]
  scale as DNA alignment coverage for common downstream handling. `has_quality` guard added
  so the function still works when the quality column is absent (coverage = NA).
- `calibrate_coverage_filter()` added to `R/calibrate.R`. Sweeps `thresholds` (default
  `seq(0, 0.99, by = 0.05)`) and returns a 10-column data frame: `threshold`, `n_queries`,
  `breadth`, `h1_pairs`, `h2_pairs`, `h1_retention`, `h2_retention`, `youden_j`,
  `discrimination`, `mean_h1_score`. H1/H2 classification auto-detected via finest rank
  in `.x`/`.y` column pairs. Categorical coverage detection (≤10 unique values) triggers
  an informational message that J/discrimination will be near-flat for acoustic data.
- `coverage_threshold()` added to `R/calibrate.R`. `keep_frac = 0.95` → threshold at
  `quantile(coverage, 0.05)`. Categorical snapping: nearest unique value with a message
  reporting the achieved vs requested retention fraction.
- `.detect_finest_rank_col()` internal helper added to `R/calibrate.R`.
- README: new "Reference Coverage Quality Filtering" section with motivation, data-type
  comparison, metric table (Youden's J explanation + acoustic caveat), and code examples
  for both `calibrate_coverage_filter()` and `coverage_threshold()`.
- `devtools::check(vignettes = FALSE)`: 0 errors, 0 warnings, 1 note (pre-existing stale top-level files).

**Session 91 (2026-05-27)**
- `read_crabs_output()` added to new `R/read_crabs.R` — reads CRABS internal-format database
  (headerless 11-column tab-delimited TSV) directly into `reference_df`. Params:
  - `rank_system`: NULL auto-detects by checking which of the 7 CRABS taxonomy columns have
    ≥1 non-NA value; otherwise takes a user-supplied coarse-to-fine vector.
  - `max_n_bases`: drop sequences longer than N bases (chimera / assembly-error filter).
  - `require_species`: default TRUE; uses `TaxaTools::is_valid_species_name()` to reject
    `sp.`, `cf.`, `aff.`, `uncultured` names.
  - `dereplicate`: collapse exact-duplicate sequences within the same species (first accession
    retained). Complementary to CRABS built-in dereplication (which works on primer-trimmed seqs).
  - Literal "NA" strings in taxonomy columns are converted to `NA` (CRABS convention for missing ranks).
  - Accession version suffix (`.1`, `.2`) stripped to match FASTA convention.
  - 16 offline tests in `tests/testthat/test-read-crabs.R`.
- `read_reference_fasta()` in `R/fetch.R` — `taxonomy_file` parameter added (Tier 2):
  - Accepts a 2-column tab-delimited TSV in QIIME2/RESCRIPt/SILVA prefix-style or positional format.
  - Header rows beginning with "Feature", "feature", or "#" are skipped automatically.
  - `taxonomy` param changed from required to `NULL`-default; exactly one of `taxonomy` or
    `taxonomy_file` must be supplied (error if both or neither).
  - Internal helpers: `.parse_taxonomy_tsv()`, `.parse_tax_string()`, `.crabs_std_hierarchy`.
  - 7 tests for taxonomy_file path in `tests/testthat/test-read-crabs.R`.
- README: new "Loading Pre-built Reference Databases" section.
- `devtools::check()`: run after implementation (target: 0 errors, 0 warnings).

**Session 93 (2026-05-27)**
- `build_image_reference()` added to new `R/build_image.R` — image analog of `build_acoustic_reference()`.
  - Joins any image classifier output to user-supplied ground-truth `images_meta` data frame.
  - `images_meta` requires: `image_path` (file stem used as join key), plus rank columns from `rank_system`.
  - `coverage`: sourced from `image_df$coverage` (bbox area) if present; falls back to
    `images_meta$quality` (per-image numeric 0--1); else NA.
  - `testid`: from `images_meta$testid` (classifier name, camera model, etc.); NA if absent.
  - 27 offline tests in `tests/testthat/test-build-image.R`.
- `inst/workflows/3c_image_reference_workflow.R` added — 9-step image reference training workflow.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (pre-existing top-level files).

**Session 94 (2026-05-28)**
- `write_reference_fasta()` added to `R/write_fasta.R`. Exports `reference_df` to FASTA with
  header `>{composite_id} {rank vals}` (NA ranks omitted) + optional companion taxonomy TSV in
  positional format compatible with `read_reference_fasta(taxonomy_file=)`. `rank_system` auto-detected
  from all non-id columns when NULL. 22 offline tests.
- `build_site_reference()` added to `R/build_site_reference.R`. High-level DNA-only wrapper:
  taxa list → NCBI fetch → optional mislabel flagging → barcode coverage audit → FASTA export.
  Parameters: `taxa`, `barcode_term`, `rank_system`, `output_dir`, `flag_errors` (default FALSE;
  requires DECIPHER), `audit_coverage` (default TRUE), `max_sequences` (5000), `max_per_species`
  (5), `species_list`, `max_date`, `ncbi_api_key`, `cache_dir`. Returns
  `list($reference_df, $errors, $census, $unreferenced)`. `output_dir` writes
  `reference.fasta` + `reference_taxonomy.tsv`.
- README: new "Building a Site-Specific Reference Library" section.
- `devtools::check()`: 0 errors, 0 warnings, 2 notes (pre-existing).

---
