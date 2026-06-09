# CLAUDE.md -- TaxaLikely
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-06-08 (Session 103 -- detect_suppressed_candidates, restore_suppressed_candidates, assign_scores score_type="direct")

---

## Package Purpose
Converts match scores (DNA percent identity, image similarity, acoustic scores) into
likelihoods for taxonomic assignment. Takes a standardized match object (from TaxaMatch
or user-supplied) and produces per-hypothesis `score_likelihood`, `score_likelihood_mean`,
`score_likelihood_sd` columns required by TaxaAssign.

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
| `score_likelihood` | numeric | Point estimate (deterministic) |
| `score_likelihood_mean` | numeric | Mean across Monte Carlo simulations |
| `score_likelihood_sd` | numeric | SD across simulations (0 if n_sims = 0) |
| `score_likelihood_cov` | numeric | Coverage-adjusted point estimate: H1 sigma inflated by `1/sqrt(coverage)`; equals `score_likelihood` when coverage absent or = 1 |

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
| `subset_local_database()` | `R/subset_db.R` | Written | Filter a large local FASTA + taxonomy file (SILVA, MIDORI2, GTDB, Greengenes2, RDP) to a user-supplied taxon list. Parses taxonomy first → O(1) ID lookup via environment hash → streams FASTA in chunks; peak memory scales with matching sequences, not total database size. Supports `.gz`-compressed FASTA. Optional `max_n_bases` and `require_species` filters. Returns `reference_df`. Reuses `.parse_taxonomy_tsv()` internal. |

### Training (fit model on reference database)

| Function | File | Status | Description |
|---|---|---|---|
| `build_sequence_matrix()` | `R/build_sequence.R` | Written | Align DNA sequences (DECIPHER), compute pairwise distance matrix → pair format for `train_likelihood_model()`. Output now includes `coverage` column (positions where both sequences are non-gap / shorter unaligned length). Renamed from `build_reference_matrix()` Session 88. |
| `flag_reference_errors()` | `R/train.R` | Written | Flag mislabeled references |
| `train_likelihood_model()` | `R/train.R` | Written | Full training pipeline -> `taxa_model_params` object; `anchor_perfect` param (default TRUE) injects synthetic perfect-match observations. Bivariate normal over `(score_logit, gap_logit)`. Coverage is a filter only — pass `min_coverage` to `evaluate_likelihoods()` at inference, not a model dimension. |

### Unified likelihood pipeline (new — Session 99)

| Function | File | Status | Description |
|---|---|---|---|
| `unreferenced_candidates()` | `R/unreferenced_candidates.R` | Written | Expand match_df with H2/H3/(H4) placeholder rows. Auto-detects `rank_system`. `include_unreferenced_family` param (default FALSE) adds H4 catch-all. Anchor = best-scoring taxon per observation. |
| `assign_scores()` | `R/assign_scores.R` | Written | Convert raw scores to `score_likelihood`. `score_type`: `"none"` (all rows = 1.0 uniform), `"direct"` (pass score column through unchanged; NA → 1.0; use after `restore_suppressed_candidates()` no-score path), `"probability"` (ratio-normalize H1; H2/H3 anchored at median same-genus/same-family H1 likelihood; H4 fixed at 0.05), `"similarity_softmax"` (exp-weighted, same H2/H3/H4 anchoring), `"similarity"` (adds `score_norm` only — pass to `model_likelihoods()`). **Single-H1 caveat**: for top-1 classifier output (one H1 row per observation), H2/H3 anchor = median(H1) = 1.0; score has no discriminating effect. Use multi-candidate output + `"probability"` to modulate likelihoods. |
| `model_likelihoods()` | `R/compute_likelihoods.R` | Written | Apply bivariate-normal model to a `scored_df` from `assign_scores(score_type="similarity")`. Thin wrapper around `evaluate_likelihoods()`; adds `score_method = "bivariate_normal"`. |
| `compute_likelihoods()` | `R/compute_likelihoods.R` | Written | Orchestrating wrapper: `unreferenced_candidates()` → `assign_scores()` → `model_likelihoods()` (similarity only). Recommended high-level entry point. Returns `list($likelihoods, $unresolved)`. |

### Inference (apply model to query observations)

| Function | File | Status | Description |
|---|---|---|---|
| `evaluate_likelihoods()` | `R/evaluate.R` | Written | Apply model to all queries; outputs likelihood object. `verbose` param (default FALSE) logs species-specific param fallback. Output includes `score_likelihood_cov`: coverage-adjusted point estimate inflating H1 sigma by `1/sqrt(coverage)` per candidate taxon (binomial SE prior); equals `score_likelihood` when coverage column is absent or all 1. |
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
| `calibrate_coverage_filter()` | `R/calibrate.R` | Written | Sweep a grid of coverage thresholds over `build_sequence_matrix()` output; return per-threshold breadth + H1/H2 discrimination metrics. Key columns: `breadth`, `h1_retention`, `h2_retention`, `youden_j` (primary — maximised at Pareto-optimal threshold), `discrimination` (ratio form), `mean_h1_score`. Detects categorical coverage (≤10 unique values) and messages that J will be near-flat. Auto-detects finest rank from `.x`/`.y` column pairs via `.detect_finest_rank_col()`. |
| `coverage_threshold()` | `R/calibrate.R` | Written | Quantile-based shortcut: returns the coverage value at the `(1 − keep_frac)` quantile so that `keep_frac` of pairs are retained (default 0.95). For categorical coverage, snaps to the nearest unique value with a message showing the achieved retention fraction. |

### No-score (prior-only) pathway

| Function | File | Status | Description |
|---|---|---|---|
| `expand_consensus_candidates()` | `R/expand_consensus.R` | **Deprecated (Session 99)** | Use `unreferenced_candidates()` + `assign_scores()` instead. Deprecated with `.Deprecated()` notice in function body. |

### Score-collapse detection and restoration

| Function | File | Status | Description |
|---|---|---|---|
| `detect_suppressed_candidates()` | `R/score_collapse.R` | Written | Diagnose which pipeline suppression rule(s) are active. Three rules: `"perfect_only"` (purity_threshold fraction of qualifying obs have only scores ≥ perfect_threshold); `"max_score_ties"` (multi-row obs all show uniform score); `"best_only"` (singleton_threshold fraction of obs have exactly 1 row). `purity_threshold` (default 0.99) and `perfect_threshold` (default 100) user-settable. Returns list: rule_detected, rules, individual logicals, diagnostic counts, example_observations. |
| `restore_suppressed_candidates()` | `R/score_collapse.R` | Written | Append same-genus congeners from `reference_df` as `hypothesis_type = "suppressed_candidate"` rows. Targeting: Rules 2/3 → all observations; Rule 1 only → observations where all scores ≥ perfect_threshold. Score imputation: `delta` (default 0.5, auto-scaled 0–100 vs 0–1) subtracted from per-obs max score. No-score path: creates synthetic `score_original` column (H1 = 1.0, restored = 1.0 − delta/100); pass to `assign_scores(score_type = "direct")`. Returns match_obj with `is_restored` column. |

**Motivation:** When BLAST uses a 100-percent rule (drop all sub-perfect hits when a perfect match exists), referenced congeners are silently suppressed. `evaluate_likelihoods()` sees only one H1 candidate (singleton mode — gap uninformative) and generates only generic `unreferenced_species` H2/H3 rows. `restore_suppressed_candidates()` replaces those generic placeholders with real referenced alternatives, enabling full bivariate-normal evaluation. See *Girella simplicidens* case (Session 101/103).

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
| 4 | `4_score_to_likelihood_workflow.R` | Convert match scores to likelihoods for TaxaAssign | `evaluate_likelihoods()` → `filter_top_hypotheses()` |
| 5 | `5_audit_coverage_workflow.R` | Audit reference completeness; constrain likelihoods | `audit_barcode_coverage()` / `audit_reference_coverage()` → `apply_coverage_constraints()` |
| 6 | `6_no_score_pathway_workflow.R` | No-score pathway: build uniform likelihoods from consensus assignments | `unreferenced_candidates()` → `assign_scores(score_type = "none")` |

Workflows 2 and 3 share `build_sequence_matrix()` — build once, reuse.
Acoustic and image data use `unreferenced_candidates()` + `assign_scores()` (no training
step — classifiers are pre-trained; TaxaLikely acts as a post-classifier calibration layer).
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
| `H1_Global_Mu` | named numeric | Global fallback mean: `c(score_logit, gap_logit)`. |
| `H1_Sigma` | matrix | 2×2 global covariance over `(score_logit, gap_logit)`. |
| `H2` | list | Missing-species params: `delta` (logit offset from H1 mean), `sigma` (2×2). |
| `H3` | list | Missing-genus params: `delta`, `sigma` (2×2). |
| `Stats` | list | Diagnostics: `AIC_Score`, `n_species`, `n_singletons`, `n_anchors`. |
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
`H2$sigma` and `H3$sigma` are **2×2 matrices** matching `H1_Sigma`. Dimnames:
`c("score_logit", "gap_logit")`.

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

## Test Coverage

All tests are fully offline (no NCBI, no DECIPHER, no external files) except `test-build.R`
which is skipped when DECIPHER/Biostrings are not installed.

| File | Functions covered | Notes |
|---|---|---|
| test-assign-scores.R | `assign_scores()` | Covers all score_type values including `"direct"`, H2/H3 anchoring, H4 behavior, single-H1 caveat |
| test-build.R | `build_sequence_matrix()` | Skipped when DECIPHER not installed (Bioconductor Suggests) |
| test-build-site-reference.R | `build_site_reference()` | Offline via `local_mocked_bindings()`; 17 tests + 1 skip (DECIPHER present) |
| test-clean.R | `remove_flagged_references()` | Fully offline |
| test-compute-likelihoods.R | `compute_likelihoods()`, `model_likelihoods()` | Fully offline with minimal model_params fixture |
| test-coverage.R | `audit_reference_coverage()`, `audit_acoustic_coverage()`, `apply_coverage_constraints()`, `calibrate_coverage_filter()`, `coverage_threshold()` | Fully offline |
| test-evaluate.R | `evaluate_likelihoods()`, `filter_top_hypotheses()` | Fully offline |
| test-expand-consensus.R | `expand_consensus_candidates()` (deprecated) | Fully offline; confirms deprecation warning fires |
| test-fetch.R | `read_reference_fasta()`, `.parse_taxonomy_tsv()`, `.parse_tax_string()` | Fully offline; NCBI fetch tests skipped |
| test-interpret.R | `interpret_model()` | Fully offline with minimal model_params fixture |
| test-normalize.R | `.normalize_scores()` | Fully offline |
| test-read-crabs.R | `read_crabs_output()`, `read_reference_fasta(taxonomy_file=)` | Fully offline; 16 + 7 tests |
| test-report_likelihood.R | `report_likelihood()` | Fully offline |
| test-subset-local-database.R | `subset_local_database()` | Fully offline; 25 tests; gz FASTA, pre-parsed taxonomy df, filters |
| test-train.R | `train_likelihood_model()`, `flag_reference_errors()` | Fully offline |
| test-unreferenced-candidates.R | `unreferenced_candidates()` | Fully offline |
| test-write-fasta.R | `write_reference_fasta()` | Fully offline |
| test-score-collapse.R | `detect_suppressed_candidates()`, `restore_suppressed_candidates()` | 24 test_that blocks; fully offline; covers all 3 rules, purity_threshold, perfect_threshold, no-score path |

---

## Statistical Design Notes

- **Score metric:** any raw match score; normalised to (0,1) then logit-transformed
- **Gap metric:** best-match logit score minus second-best logit score -- key discriminator
- **H1 (Known Species):** bivariate normal over `(score_logit, gap_logit)`.
  Species-specific score + gap means with Empirical Bayes shrinkage toward global mean.
- **H2 (Missing Species):** H1 distribution shifted left by `H2$delta` on score axis.
- **H3 (Missing Genus):** shifted further left by `H3$delta` = `H2$delta + 2.0`
- **Singleton queries:** 1D normal (score only) when only one candidate exists (gap uninformative).
- **Pseudo-data anchoring:** `anchor_perfect = TRUE` (default) injects synthetic
  perfect-match rows (score = logit(1-ε), gap = 95th percentile of real positive gaps)
  into training data. Prevents the "perfection penalty". Count = max(5, 10% of data).
- **Shrinkage:** `w = N / (N + prior_weight)`; per-species score variance + gap mean shrunk
  toward global. Default `prior_weight = 10.0`.
- **Monte Carlo:** n_sims perturbations of score_logit → `score_likelihood_mean` + `score_likelihood_sd`.
- **Median-across-references:** `evaluate_likelihoods()` takes the **median** score
  per taxon_name across multiple reference accessions before likelihood calculation.
- **Coverage filter (not a model dimension):** pass `min_coverage` to `evaluate_likelihoods()`
  to pre-filter candidates below an alignment/detection quality threshold. Use
  `calibrate_coverage_filter()` on the training matrix to find the Pareto-optimal threshold.

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

### Single H2/H3 anchor — non-best genera get no unreferenced hypothesis
`.evaluate_one_query()` generates exactly one H2 row (unreferenced species in the
best candidate's genus) and one H3 row (unreferenced genus in the best candidate's
family), both anchored at the single globally best-scoring candidate. This is
intentional: when one genus clearly dominates, its unreferenced congeners are the
relevant alternative hypotheses, and the gap feature already signals ambiguity when
genera are nearly tied. The implicit assumption is that near-tied multi-genus
observations are routed through the consensus/upranking pathway (uniform likelihoods)
rather than `evaluate_likelihoods()`. Known limitation: near-tied multi-genus queries
that bypass upranking will not receive unreferenced hypotheses for the non-best genus.

### expand_unreferenced_hypotheses() workflow order
`expand_unreferenced_hypotheses()` must run **before** `apply_coverage_constraints()`.
Coverage constraints operate on `hypothesis_type` and `taxon_name`; if constraints are
applied first (zeroing the generic H2 row), expansion will produce named rows with
non-zero likelihoods that bypass the constraint. Correct order:
`evaluate_likelihoods()` → `filter_top_hypotheses()` → `expand_unreferenced_hypotheses()`
→ `apply_coverage_constraints()`.

---

## Session Notes

Sessions 30–94 archived in `ecosystem_docs/session_notes/TaxaLikely_sessions.md`.

**Session 100 (2026-06-03/04): Trivariate revert; coverage sigma-inflation (score_likelihood_cov)**

Trivariate coverage model (rejected): explored making coverage a third dimension of the
bivariate normal, but premise validation on `build_sequence_matrix()` output showed H1
(within-species) training pairs are nearly all coverage ≈ 1 (mean 0.991, var 0.002) while
H2 cross-species pairs are much more variable (mean 0.908, var 0.041). Because there is
no within-H1 coverage variation, the model cannot estimate a coverage–score relationship.
Trivariate approach reverted; coverage remains a hard filter only via `min_coverage`.

New: `score_likelihood_cov` column added to `evaluate_likelihoods()` output. Applies a
post-hoc sigma inflation at inference time using a prior (binomial SE argument):
σ_eff = σ / sqrt(coverage). Only the [1,1] element of H1_Sigma is inflated; H2/H3 sigmas
are global fixed parameters and are not modified. Key behavior: for scores near the H1
mean (good within-species matches), widening sigma lowers the peak density → negative
delta (primary intended effect — penalises good matches observed at low coverage). For
scores far below the H1 mean (cross-species matches), widening sigma fattens the left
tail → positive delta (secondary, low-relevance effect). Crossover at exactly ±1 sigma
from the H1 mean. Column added as a parallel output only (non-breaking); `score_likelihood`
is unchanged and remains the default for TaxaAssign unless the user switches.

Other changes this session: Workflow 3 fully rewritten (removed stale trivariate
references; added coverage-by-hypothesis-type diagnostic; added demo of
score_likelihood_cov using within-species pairs with coverage < 0.99). README updated
with `score_likelihood_cov` in the Quick Start output and a Statistical Design bullet
explaining the formula, direction of effect, and why coverage is not a model dimension.
`train.R` minor cleanup (roxygen, h2_sigma_mat moved outside conditional).
