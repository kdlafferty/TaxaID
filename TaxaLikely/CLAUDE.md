# CLAUDE.md -- TaxaLikely
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-27 (Session 89 -- audit_acoustic_coverage new function; data-type scope notes)

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
| `read_reference_fasta()` | `R/fetch.R` | Written | Read local FASTA + user-supplied taxonomy table → `reference_df`. For CRUX, GenBank dumps, custom databases. |
| `fetch_reference_recordings()` | `R/fetch_recordings.R` | Written | Fetch bird sound recordings from Xeno-canto API v3. Returns metadata table for acoustic reference training. `api_key` required (read from `XC_API_KEY` env var). `quality` A-E filter; `max_per_species` cap; optional `download = TRUE`. Internals: `.xc_query_all()`, `.xc_standardize_cols()`, `.parse_xc_duration()`. |

### Training (fit model on reference database)

| Function | File | Status | Description |
|---|---|---|---|
| `build_sequence_matrix()` | `R/build_sequence.R` | Written | Align DNA sequences (DECIPHER), compute pairwise distance matrix → pair format for `train_likelihood_model()`. Renamed from `build_reference_matrix()` Session 88. |
| `build_acoustic_reference()` | `R/build_acoustic.R` | Written | Acoustic analog of `build_sequence_matrix()`. Joins BirdNET detections to Xeno-canto ground truth; labels H1/H2/H3; maps `type` → `testid`. Returns same `.x`/`.y` pair format. Train one model per `testid` type (song, call) as eDNA trains per marker. |
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

### Match object cleaning

| Function | File | Status | Description |
|---|---|---|---|
| `remove_flagged_references()` | `R/clean.R` | Written | Remove mislabeled accessions from match_df using `flag_reference_errors()` output. Handles version suffix stripping. `remove_unverified_singletons` param (default FALSE). |

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
| *(removed — Session 57)* | `R/coverage.R` | `.barcode_length_defaults`, `.resolve_barcode_lengths()`, `.is_valid_species_name()` moved to TaxaTools as exports; now called as `TaxaTools::resolve_barcode_lengths()` and `TaxaTools::is_valid_species_name()` |
| `.build_search_term()` | `R/fetch.R` | Construct NCBI nucleotide search query from taxon + barcode_term + dates |
| `.fetch_summaries_batched()` | `R/fetch.R` | Batched NCBI summary retrieval (accession, taxid, length); exponential backoff |
| `.fetch_taxonomy_map()` | `R/fetch.R` | Batched NCBI taxonomy XML → full lineage lookup table |
| `.fetch_fasta_batched()` | `R/fetch.R` | Batched FASTA download from NCBI nucleotide |
| `.parse_fasta_text()` | `R/fetch.R` | Parse FASTA text into data.frame(composite_id, sequence) |

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

**Session 30 (2026-03-27)**
- Package scaffold created
- Source file: `~/Rscripts/eDNA/Bayesian  Workflow/Universal_Biological_Classifier_Working_2.R`
- All modeling + inference functions assigned to TaxaLikely
- TaxaMatch confirmed as thin shell (standardization only)
- Sample context confirmed as separate table joined downstream

**Session 31 (2026-03-27)**
- All functions written and passing check (0 errors, 0 warnings, 0 notes)
- 74 tests passing, 3 skipped (DECIPHER not installed in check environment)
- Key refactoring decisions documented above under "Critical Design Decisions"
- Workflow script written at: `inst/TaxaLikely_workflow.R`

**Session 32 (2026-03-27)**
- End-to-end workflow debugged against real MiFish eDNA data (tidewater goby dataset)
- `evaluate_likelihoods()` return type changed: now returns named list `$likelihoods` + `$unresolved`
  - `$unresolved`: original match_df rows for observation_ids that produced no usable likelihoods
  - Warning emitted with count when `$unresolved` is non-empty
- `audit_reference_coverage()`: `taxize` dependency removed entirely; replaced with direct
  NCBI taxonomy queries via `rentrez` (`entrez_search` + `entrez_summary`)
  - `database` parameter removed (NCBI-only now, consistent with reference sequences)
  - `stringr` also removed from Imports (no longer needed)
  - `rentrez` moved from Suggests to Imports
- `inst/real_matrix.rds` and `inst/real_likelihoods.rds` added to `.Rbuildignore`
- Workflow renamed to `inst/TaxaLikely_workflow.R`; Stage B fully runnable (fetches sequences
  via rentrez, builds reference matrix, trains model, evaluates likelihoods)

**Session 33 (2026-03-28)**
- `audit_barcode_coverage()` added to `R/coverage.R` -- initial version for eDNA/barcode data
  - `.is_valid_species_name()` filters "sp.", "cf.", uncultured, and non-binomial NCBI names
  - `barcode_term` accepts a character vector; terms are OR-ed in the NCBI query
  - `max_date` parameter (NCBI `[PDAT]` filter) restricts results to sequences available by a
    given date -- use to match the state of GenBank when your reference library was built
  - `min_len` / `max_len` auto-resolved from an internal lookup keyed on `barcode_term`
  - `audit_reference_coverage()` retained unchanged for non-barcode libraries
- Unreferenced species expansion gap identified: `evaluate_likelihoods()` H2 rows are generic (genus-level);
  no function yet expands them into named species for TaxaExpect. `expand_unreferenced_hypotheses()`
  is planned. See Known Footguns.
- `inst/TaxaLikely_workflow.R` Stage C updated to use `audit_barcode_coverage()`

**Session 34 (2026-03-29)**
- `audit_barcode_coverage()` completely redesigned after debugging against real tidewater goby dataset
  - **Corrected unreferenced definition:** unreferenced = described taxon with NO barcode sequence (count = 0).
    Previous (wrong) definition was: species with sequences absent from user's reference.
    This distinction is fundamental -- a true unreferenced species can never be a match candidate regardless
    of what reference library the user has built.
  - **NCBI API reliability fixes** (debugging revealed multiple failure modes):
    - `entrez_search` on genus-level nucleotide queries → HTTP 500 for species-rich genera
      (Hybognathus, Notropis, Gambusia). Fixed by switching to taxonomy-first approach:
      3 lightweight taxonomy API calls per genus to get the species list, then per-species
      nucleotide queries only.
    - `datetype/mindate/maxdate` as separate API params → silent HTTP 500, all counts 0.
      Fixed by embedding date as `[PDAT]` range in the query term string (following the
      `f_search_sequence_by_gene` pattern from the UBC source file).
    - `retmax=0` count queries (no ID list returned) eliminate all XML parse errors.
    - 3-attempt exponential backoff: `Sys.sleep(attempt)` (1s, 2s, 3s); NA on failure
      treated conservatively as unreferenced.
  - **Census columns redesigned:** `have`/`missing_count`/`is_complete` →
    `in_reference`/`has_seqs_not_in_ref`/`unreferenced`/`is_complete`
    (`is_complete` = both gaps are zero)
  - **`species_list` parameter added:** optional user-supplied character vector from
    GBIF/FishBase/WoRMS for more complete genus coverage than NCBI taxonomy alone.
    Species absent from all sources are also unreferenced but will be missed.
  - **Deprecation note added** to roxygen docs: function is correct but slow for large genera;
    will be superseded by `suggest_unreferenced_species()` (LLM-first architecture, in TaxaAssign)
- **LLM-first unreferenced species detection architecture agreed** (implemented in TaxaAssign as `suggest_unreferenced_species()`):
  1. Submit genus list to LLM → get plausible species per genus (cheap, one call)
  2. Remove species already in match_df (have references by definition)
  3. NCBI barcode-count queries only on the plausible remainder (much smaller list)
  4. Integration points: `assign_taxa_llm()` (TaxaAssign, LLM-shortcut workflow) via `unreferenced_taxa=` param
  5. Retains an "unknown/implausible" species row for taxa outside the LLM's plausible set
- `inst/TaxaLikely_workflow.R` Stage C documentation updated with corrected unreferenced species definition
  and new census column names; `species_list` and `max_date` shown as commented options
- `inst/TaxaAssign_llm_workflow.R` Section 4 comment block rewritten with correct unreferenced species
  definition and Fundulus parvipinnis example; `species_list` and `ncbi_api_key` shown

**Session 40 (2026-03-31)**
- `expand_unreferenced_hypotheses()` designed, implemented, then moved to TaxaAssign
  (requires both TaxaLikely + TaxaExpect outputs; belongs at their convergence point)
- TaxaLikely workflow (`inst/TaxaLikely_workflow.R`) ends at Stage C (coverage audit);
  pointer added to `TaxaAssign_bayesian_workflow.R` for the next step
- "Ghost prior values" heading in `TaxaAssign/inst/PRIOR_LIKELIHOOD_MATCHING.md` (line 160)
  identified as remaining ghost-terminology remnant — not yet renamed

**Session 39 (2026-03-31)**
- "Ghost" terminology replaced with "unreferenced" throughout:
  - `audit_barcode_coverage()`: return value `$ghosts` → `$unreferenced`
  - Census column `ghosts` → `unreferenced` in census data frame
  - `audit_reference_coverage()`: return value `$ghosts` → `$unreferenced`
  - Roxygen docs, inline comments, workflow scripts, test names updated
  - `expand_ghost_hypotheses()` (planned) → renamed to `expand_unreferenced_hypotheses()`

**Session 50 (2026-04-07)**
- `fetch_reference_sequences()` added to `R/fetch.R` -- search NCBI by taxon + barcode marker,
  bridge to taxonomy DB for full lineage, filter/downsample, download FASTA → `reference_df`.
  Based on `GetNCBIsequences3.R` (UBC lineage). Features: count-first estimation with
  `max_sequences` safety valve, resumable via `cache_dir`, stratified downsampling
  (`max_per_species`, `max_per_genus`), length auto-detection from barcode_term,
  exponential backoff on NCBI API failures.
- `read_reference_fasta()` added to `R/fetch.R` -- read local FASTA + user-supplied taxonomy
  table → `reference_df`. For users with existing databases (CRUX, GenBank dumps, custom FASTA).
  Taxonomy as separate data frame (Option B from design discussion); no FASTA header parsing.
- `xml2` added to DESCRIPTION Imports (taxonomy XML parsing in `.fetch_taxonomy_map()`)
- 5 internal helpers: `.build_search_term()`, `.fetch_summaries_batched()`,
  `.fetch_taxonomy_map()`, `.fetch_fasta_batched()`, `.parse_fasta_text()`
- **Workflow scripts completely reorganized**: monolithic `inst/TaxaLikely_workflow.R`
  replaced by 5 self-contained scripts in `inst/workflows/`:
  1. `1_fetch_references_workflow.R` (NCBI fetch or local FASTA)
  2. `2_flag_errors_workflow.R` (error detection + exploration)
  3. `3_train_model_workflow.R` (model training + interpretation)
  4. `4_score_to_likelihood_workflow.R` (match → likelihoods, with error filtering)
  5. `5_audit_coverage_workflow.R` (coverage audit + constraint application)
- Error-to-downstream bridge: Workflow 4 includes one-liner to remove flagged reference
  errors from match_df before `evaluate_likelihoods()`. No dedicated function needed.
- Design decision: `fetch_reference_sequences()` lives in TaxaLikely (not TaxaFetch)
  because it serves TaxaLikely workflows specifically -- the broader NCBI search (by taxon +
  marker, not by accession) is needed for model building, not match data.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 51 (2026-04-08)**
- `anchor_perfect` parameter added to `train_likelihood_model()` (default `TRUE`):
  injects synthetic perfect-match pseudo-data to prevent the "perfection penalty"
  (100% match penalized because model never saw perfect scores in training).
  Anchor rows use `rank_code_a = "ANCHOR_PERFECT"` and are excluded from H1_Lookup.
  `n_anchors` added to `Stats` slot.
- `inst/plot_likelihood_landscape.R` created: standalone two-panel base-R visualization
  of H1/H2 density surfaces with three example points (A = correct species, B = wrong
  species, U = unreferenced). Previously was an exported function in R/interpret.R;
  moved to inst/ because it is for presentations/manuscripts, not programmatic use.
- `inst/TaxaLikely_supplemental_methods.md` created: 10-section statistical methods document adapted
  from `Match_to_Likelihoods_Text.docx`, updated to TaxaLikely/TaxaID terminology.
  Covers: problem statement, statistical framework, feature engineering, three hypotheses,
  hierarchical parameter estimation (including anchoring), likelihood calculation,
  multi-candidate evaluation, Monte Carlo uncertainty, reference QC, visualization.
- `Figure_Likelihood_Calibration.R` (old eDNA/Bayesian Workflow file) rewritten:
  old ggplot2+mvtnorm single-panel with 5 points replaced with base-R two-panel
  A/B/U design matching inst/ version. Points to TaxaLikely inst/ as canonical.
- `TaxaID_presentation.qmd` updated: new "Score + Gap" slide with embedded base-R
  two-panel figure; TaxaLikely function table corrected to 11 functions.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (stale .rds files at top level)

**Session 57 (2026-04-15) — Prompts 15-16**
- `.build_search_term()` in `R/fetch.R`: barcode terms now mapped to NCBI `[GENE]` field tags
  via internal `gene_map` (Prompt 15, GITA G19). Gene names (COI, cytb, 12S, etc.) use `[GENE]`;
  primer names (MiFish, Teleo) fall back to `[All Fields]`.
- Internal helpers `.barcode_length_defaults`, `.resolve_barcode_lengths()`, `.is_valid_species_name()`
  removed from `R/coverage.R` (Prompt 16, D3/D4). Now called as `TaxaTools::resolve_barcode_lengths()`
  and `TaxaTools::is_valid_species_name()`. TaxaTools was already in Imports.
- `inst/TaxaLikely_workflow.R` deleted (X5 — superseded by 5 workflow scripts in `inst/workflows/`).
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 61 (2026-04-29)**
- `remove_flagged_references()` added to `R/clean.R` — new exported function for removing
  mislabeled accessions from match_df. Takes `match_df` + `reference_errors` (output of
  `flag_reference_errors()`). Strips accession version suffixes automatically. Default
  removes only `"likely_mislabeled"`; `remove_unverified_singletons = TRUE` also removes
  `"unverified_singleton_high_match"`. 13 tests in `test-clean.R`.
- `train_likelihood_model()`: now stores the error list as `model_params$reference_errors`
  (the full output of `flag_reference_errors()` called internally). The error object travels
  with the model — downstream wrappers auto-filter without separate file management.
- `rank_system` auto-detection: both `train_likelihood_model()` and `evaluate_likelihoods()`
  now default `rank_system = NULL` and auto-detect from input columns (`.x`-suffixed columns
  in training data, direct column names in match_df). Prevents rank mismatch errors when
  model and match_df have different rank columns available.
- Workflow 4 (`inst/workflows/4_score_to_likelihood_workflow.R`): updated to use
  `remove_flagged_references()` instead of manual accession filtering. Shows
  `model_params$reference_errors` as primary source.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (pre-existing stale CSV)

**Session 73 (2026-05-14)**
- `fetch_reference_sequences()`: per-taxon fetch loop body wrapped in `tryCatch` so NCBI
  rate-limit or parse errors skip one taxon with a warning instead of crashing the entire run.
- `fetch_reference_sequences()`: `cache_dir` default changed from `NULL` to `tempdir()`.
  Cached per-taxon metadata files enable transparent resume after partial failures.
- `fetch_reference_sequences()`: fixed `finest_rank` scoping bug — variable was defined
  inside per-taxon `tryCatch` block but used in the final summary message after the loop.
  Added `finest_rank <- tolower(rank_system[length(rank_system)])` before the message.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename across all R source, tests, inst/workflows/, DESCRIPTION, README
- `globalVariables("sample_id")` → `globalVariables("observation_id")` in `R/evaluate.R`
- Match Object Interface and Likelihood Object Interface docs updated in CLAUDE.md
- 143 tests passing; `devtools::check()` clean after reinstall

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaLikely-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), model
  registry enhancements, WERC peer review integration, ecosystem_docs cleanup, renv removal.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 87 (2026-05-26)**
- `fetch_reference_recordings()` added to `R/fetch_recordings.R` — fetch bird sound recordings
  from Xeno-canto for acoustic likelihood model training. Xeno-canto is the NCBI analog for
  bird acoustics: public reference database with ground-truth species labels + quality grades.
- **API v3 upgrade**: Xeno-canto retired the public v2 API (now returns 404). v3 requires an
  API key (registered XC members only). `api_key = Sys.getenv("XC_API_KEY")` param added;
  clear error with registration URL when key is missing. Endpoint updated to
  `https://xeno-canto.org/api/3/recordings`; `per_page = 500L` maximises results per page.
- `httr2` added to Suggests (requireNamespace guard at function entry).
- Internal helpers: `.xc_query_all()` (pagination + key passing), `.xc_standardize_cols()`
  (field rename + species column build + duration parse), `.parse_xc_duration()` ("m:ss" → s).
- Returns: `recording_id` (XC-prefixed), `species`, `genus`, `common_name`, `quality`,
  `type`, `country`, `location`, `lat`, `lng`, `duration_s`, `date`, `license`, `file_url`,
  `also_species`, `local_path`. `attr(result, "xc_query")` stores the original species arg.
- Offline validation tests + API-key-guarded online tests in `test-fetch_recordings.R`.
- Acoustic reference training workflow:
  1. `fetch_reference_recordings()` → download audio
  2. Run BirdNET-Analyzer on audio
  3. `TaxaMatch::read_birdnet_output()` → join back to ground-truth species by `source_file`
  4. Label H1/H2/H3 → `train_likelihood_model()`
- `devtools::check()`: 0 errors, 0 notes (2 pre-existing vignette warnings).

**Session 88 (2026-05-26)**
- **`duplicate 'row.names' are not allowed` bug fixed** in `fetch_reference_recordings()` when
  querying multiple quality grades (e.g. `quality = c("A", "B")`). Root cause: `httr2::resp_body_json(simplifyVector = TRUE)`
  delegated to jsonlite which internally calls `.rowNamesDF<-` when building a data frame from
  the `also` field (variable-length JSON arrays per recording). Fix: switched to `simplifyVector = FALSE`
  so recordings are always returned as a list-of-lists; added `.xc_rbind()` internal helper with
  offset-based unique row names for all combine operations.
- `build_reference_matrix()` renamed to `build_sequence_matrix()` (file `R/build.R` → `R/build_sequence.R`).
  Rationale: the function is DNA-sequence-specific; the generic name conflicted as the ecosystem
  expanded to acoustic observations. Batch sed rename across 36 files. `devtools::document()` regenerated
  NAMESPACE + Rd. Backward-incompatible: callers must update to `build_sequence_matrix()`.
- `build_acoustic_reference()` added to new `R/build_acoustic.R` — acoustic analog of
  `build_sequence_matrix()`. Joins `read_birdnet_output()` results to Xeno-canto ground-truth
  labels and produces pair format compatible with `train_likelihood_model()`. Key design:
  - Join key: `sub(".BirdNET.results.csv", "", source_file)` → `tools::file_path_sans_ext(basename(local_path))`
  - `merge(gt_lookup, birdnet_df, by = "file_stem")` — ground truth in `.x`, BirdNET detection in `.y`
  - Detection rank within window: `sequence(rle(observation_id)$lengths)` after sort by score desc
  - `testid = recordings_meta$type` (Xeno-canto recording type: "song", "call", etc.)
  - Recording type is the acoustic analog of `testid` (barcode marker) in eDNA; train one model per type
  - `exclude_background` param: drops detections of species in `recordings_meta$also_species`
  - 25 tests in `tests/testthat/test-build-acoustic.R` (all offline)
- TaxaMatch and TaxaLikely READMEs updated with real BirdNET-Analyzer installation instructions,
  Python analysis script example, expected CSV format, and reference training workflow sections.
- `devtools::check(vignettes = FALSE)`: 0 errors, 0 warnings, 0 notes.

---

