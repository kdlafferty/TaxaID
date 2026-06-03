# TaxaLikely Session Notes Archive
# Sessions 30–88. Current sessions (90+) live in TaxaLikely/CLAUDE.md.

**Session 99 (2026-06-02)**
- Phase 1 — column renames (ecosystem-wide):
  - `score` → `score_original` in TaxaMatch output and all TaxaLikely/TaxaAssign consumers
  - `likelihood_point_est`/`_mean`/`_sd` → `score_likelihood`/`_mean`/`_sd`
- Phase 2 — unified modular likelihood pipeline (new functions):
  - `unreferenced_candidates()`: adds H2 (unreferenced_species) and H3 (unreferenced_genus)
    placeholder rows per observation; auto-detects rank_system; optional H4 (unreferenced_family)
    via `include_unreferenced_family = TRUE`
  - `assign_scores()`: sets `score_likelihood` by `score_type`:
    - `"none"` — all rows = 1.0 (morphology / expert IDs / upranked consensus)
    - `"probability"` — ratio-normalize multi-candidate softmax scores (iNat CV, BirdNET full output)
    - `"similarity_softmax"` — exp-weighted for similarity scores without a trained model
    - `"similarity"` — adds `score_norm` only; pass to `model_likelihoods()` for bivariate-normal
    - H2/H3 anchored at median same-genus/same-family H1 likelihood; H4 fixed at 0.05
    - **Single-H1 caveat**: for top-1 classifier output, H2/H3 anchor = 1.0; confidence score
      has no discriminating effect — use multi-candidate output + `"probability"` instead
  - `model_likelihoods()`: thin wrapper applying bivariate-normal model to `score_type="similarity"` output
  - `compute_likelihoods()`: orchestrating wrapper — `unreferenced_candidates()` → `assign_scores()` →
    `model_likelihoods()`; recommended high-level entry point for DNA scored pathway
- `expand_consensus_candidates()` deprecated with `.Deprecated()` notice; function retained in
  `R/expand_consensus.R` for backward compatibility
- Workflow 6 (`6_no_score_pathway_workflow.R`) rewritten for new API; now includes auto taxonomy
  join block for `posterior_consensus()` output (which lacks family/genus/species columns)
- `expand_consensus_demo.R` rewritten for new API (3 demos replacing 7 old test cases)
- `inst/test_session99.R` added: 22-assertion smoke test covering all new pipeline entry points
- DAG/README updates: main TaxaID README flowchart updated (removed build_acoustic/image_reference,
  added no-score pathway node, fixed consensus_taxonomy label); TaxaLikely README inference
  section, BirdNET section, and No-Score Pathway section rewritten

**Session 98 (2026-06-01)**
- Cross-package test cleanup (no function changes):
  - TaxaHabitat `test-assign_habitat_biological.R`: replaced 4 skeletal tests with TaxaFetch's
    comprehensive 542-line version (Parts A-J); 143 tests now passing in TaxaHabitat.
  - TaxaHabitat `test-build_habitat_prompt.R`: replaced 5 geographic_context-only tests with
    merged file combining TaxaFetch's comprehensive Parts A-G + geographic_context as Part H.
  - TaxaFetch: deleted both orphaned test files (functions live in TaxaHabitat).
  - TaxaExpect: deleted `inst/6_prior_wrapper.R` (9-line stub with undefined variable;
    superseded by `run_bayesian_pipeline()`).

**Session 97 (2026-06-01)**
- Acoustic/image workflow redesigned: TaxaLikely now operates as a post-classifier layer only
- Removed: `build_acoustic_reference()`, `build_image_reference()`, `fetch_reference_recordings()`
- Removed: workflow scripts `3b_acoustic_reference_workflow.R`, `3c_image_reference_workflow.R`
- Modified: `expand_consensus_candidates()` gains optional `score_col` param
  - No score → all likelihoods = 1.0 (existing behavior)
  - With score → L(H1) = score; L(all other candidates) = 1 − score
  - Covers BirdNET top-1 use case (single candidate with classifier confidence)
- Added to TaxaTools: `common_to_scientific()` — LLM-assisted common name → scientific name
  with optional backbone verification via `verify_taxon_names()`; needed for classifiers
  that output common names rather than scientific names
- Three match scenarios now handled: (A) multiple candidates + scores → `evaluate_likelihoods()`;
  (B) single candidate + score → `expand_consensus_candidates(score_col=)`;
  (C) single candidate no score → `expand_consensus_candidates()` (uniform likelihoods)

**Session 30 (2026-03-27)**
- Package scaffold created
- Source file: `~/Rscripts/eDNA/Bayesian  Workflow/Universal_Biological_Classifier_Working_2.R`
- All modeling + inference functions assigned to TaxaLikely
- TaxaMatch confirmed as thin shell (standardization only)
- Sample context confirmed as separate table joined downstream

**Session 31 (2026-03-27)**
- All functions written and passing check (0 errors, 0 warnings, 0 notes)
- 74 tests passing, 3 skipped (DECIPHER not installed in check environment)
- Key refactoring decisions documented in CLAUDE.md under "Critical Design Decisions"
- Workflow script written at: `inst/TaxaLikely_workflow.R`

**Session 32 (2026-03-27)**
- End-to-end workflow debugged against real MiFish eDNA data (tidewater goby dataset)
- `evaluate_likelihoods()` return type changed: now returns named list `$likelihoods` + `$unresolved`
- `audit_reference_coverage()`: `taxize` dependency removed; replaced with direct NCBI taxonomy via `rentrez`
  - `database` parameter removed (NCBI-only now); `stringr` also removed from Imports
  - `rentrez` moved from Suggests to Imports
- `inst/real_matrix.rds` and `inst/real_likelihoods.rds` added to `.Rbuildignore`

**Session 33 (2026-03-28)**
- `audit_barcode_coverage()` added to `R/coverage.R` — initial version for eDNA/barcode data
  - `barcode_term` accepts a character vector; terms OR-ed in NCBI query
  - `max_date` parameter (NCBI `[PDAT]` filter)
  - `min_len` / `max_len` auto-resolved from internal lookup
- Unreferenced species expansion gap identified; `expand_unreferenced_hypotheses()` planned

**Session 34 (2026-03-29)**
- `audit_barcode_coverage()` completely redesigned after debugging against real tidewater goby dataset
  - **Corrected unreferenced definition:** unreferenced = NO barcode sequence (count=0), not merely absent from user reference
  - NCBI API reliability fixes: taxonomy-first species list; `retmax=0`; `[PDAT]` in term string; exponential backoff
  - Census redesigned: `in_reference`/`has_seqs_not_in_ref`/`unreferenced`/`is_complete`
  - `species_list` parameter added
  - Deprecation note added (will be superseded by `suggest_unreferenced_species()`)
- LLM-first unreferenced species detection architecture agreed (implemented in TaxaAssign)

**Session 39 (2026-03-31)**
- "Ghost" terminology replaced with "unreferenced" throughout:
  - `audit_barcode_coverage()` return value `$ghosts` → `$unreferenced`
  - Census column `ghosts` → `unreferenced`
  - `audit_reference_coverage()` return value `$ghosts` → `$unreferenced`

**Session 40 (2026-03-31)**
- `expand_unreferenced_hypotheses()` designed, implemented, then moved to TaxaAssign
- TaxaLikely workflow ends at Stage C (coverage audit); pointer added to TaxaAssign Bayesian workflow

**Session 50 (2026-04-07)**
- `fetch_reference_sequences()` added to `R/fetch.R`
- `read_reference_fasta()` added to `R/fetch.R`
- `xml2` added to DESCRIPTION Imports
- 5 internal helpers: `.build_search_term()`, `.fetch_summaries_batched()`, `.fetch_taxonomy_map()`, `.fetch_fasta_batched()`, `.parse_fasta_text()`
- **Workflow scripts reorganized**: monolithic `inst/TaxaLikely_workflow.R` replaced by 5 scripts in `inst/workflows/`
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 51 (2026-04-08)**
- `anchor_perfect` parameter added to `train_likelihood_model()` (default TRUE)
- `inst/plot_likelihood_landscape.R` created: standalone two-panel base-R visualization
- `inst/TaxaLikely_supplemental_methods.md` created: 10-section statistical methods document
- `devtools::check()`: 0 errors, 0 warnings, 1 note (stale .rds files at top level)

**Session 57 (2026-04-15)**
- `.build_search_term()`: barcode terms mapped to NCBI `[GENE]` field tags
- Internal helpers `.barcode_length_defaults`, `.resolve_barcode_lengths()`, `.is_valid_species_name()` moved to TaxaTools
- `inst/TaxaLikely_workflow.R` deleted (superseded by 5 workflow scripts)
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 61 (2026-04-29)**
- `remove_flagged_references()` added to `R/clean.R`
- `train_likelihood_model()`: now stores error list as `model_params$reference_errors`
- `rank_system` auto-detection for both `train_likelihood_model()` and `evaluate_likelihoods()`
- `devtools::check()`: 0 errors, 0 warnings, 1 note (pre-existing stale CSV)

**Session 67 (2026-05-04)**
- `lme4`, `rentrez`, `xml2` moved to Suggests (all had `requireNamespace()` guards already)
- `@importFrom xml2` removed. Reduces install footprint.

**Session 73 (2026-05-14)**
- `fetch_reference_sequences()`: per-taxon tryCatch; `cache_dir` default changed to `tempdir()`
- Fixed `finest_rank` scoping bug in `fetch_reference_sequences()`
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename across all R source, tests, inst/workflows/, DESCRIPTION, README
- `globalVariables("sample_id")` → `globalVariables("observation_id")` in `R/evaluate.R`
- 143 tests passing; `devtools::check()` clean after reinstall

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaLikely-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools),
  model registry enhancements, WERC peer review, ecosystem_docs cleanup, renv removal.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).

**Session 87 (2026-05-26)**
- `fetch_reference_recordings()` added to `R/fetch_recordings.R` — Xeno-canto API v3
- **API v3 upgrade**: v2 retired; v3 requires API key (`XC_API_KEY` env var)
- `httr2` added to Suggests. Internal helpers: `.xc_query_all()`, `.xc_standardize_cols()`, `.parse_xc_duration()`
- Acoustic reference training workflow outlined (4 steps)
- `devtools::check()`: 0 errors, 0 notes (2 pre-existing vignette warnings).

**Session 88 (2026-05-26)**
- **`duplicate 'row.names'` bug fixed** in `fetch_reference_recordings()` when querying multiple quality grades.
  Fix: `simplifyVector = FALSE` + `.xc_rbind()` internal helper with offset-based unique row names.
- `build_reference_matrix()` renamed to `build_sequence_matrix()` (file `R/build.R` → `R/build_sequence.R`).
  Batch rename across 36 files. Backward-incompatible.
- `build_acoustic_reference()` added to new `R/build_acoustic.R`
  - Join key: `sub(".BirdNET.results.csv", "", source_file)` → `tools::file_path_sans_ext(basename(local_path))`
  - `testid = recordings_meta$type` (recording type: "song", "call", etc.)
  - `exclude_background` param: drops detections of background species
  - 25 tests in `tests/testthat/test-build-acoustic.R`
- `devtools::check(vignettes = FALSE)`: 0 errors, 0 warnings, 0 notes.

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
- README: new "Reference Coverage Quality Filtering" section.
- `devtools::check(vignettes = FALSE)`: 0 errors, 0 warnings, 1 note (pre-existing stale top-level files).

**Session 91 (2026-05-27)**
- `read_crabs_output()` added to new `R/read_crabs.R` — reads CRABS internal-format database
  (headerless 11-column tab-delimited TSV) directly into `reference_df`. Params:
  `rank_system` (NULL auto-detects), `max_n_bases`, `require_species` (default TRUE),
  `dereplicate`. Literal "NA" strings converted to NA. Accession version suffix stripped.
  16 offline tests in `tests/testthat/test-read-crabs.R`.
- `read_reference_fasta()` — `taxonomy_file` parameter added. Accepts 2-column TSV in
  QIIME2/RESCRIPt/SILVA prefix-style or positional format. `taxonomy` param now NULL-default;
  exactly one of `taxonomy` or `taxonomy_file` must be supplied.
  Internal helpers: `.parse_taxonomy_tsv()`, `.parse_tax_string()`, `.crabs_std_hierarchy`.
  7 tests in `tests/testthat/test-read-crabs.R`.
- README: new "Loading Pre-built Reference Databases" section.

**Session 93 (2026-05-27)**
- `build_image_reference()` added to new `R/build_image.R` — image analog of `build_acoustic_reference()`.
  Joins image classifier output to user-supplied ground-truth `images_meta`. `coverage` from
  `image_df$coverage` (bbox area) or `images_meta$quality`; `testid` from `images_meta$testid`.
  27 offline tests in `tests/testthat/test-build-image.R`.
- `inst/workflows/3c_image_reference_workflow.R` added.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (pre-existing top-level files).

**Session 94 (2026-05-28)**
- `write_reference_fasta()` added to `R/write_fasta.R`. Exports `reference_df` to FASTA +
  optional companion taxonomy TSV in positional format compatible with
  `read_reference_fasta(taxonomy_file=)`. `rank_system` auto-detected when NULL. 22 offline tests.
- `build_site_reference()` added to `R/build_site_reference.R`. High-level DNA-only wrapper:
  taxa list → NCBI fetch → optional mislabel flagging → barcode coverage audit → FASTA export.
  Returns `list($reference_df, $errors, $census, $unreferenced)`. `output_dir` writes
  `reference.fasta` + `reference_taxonomy.tsv`.
- README: new "Building a Site-Specific Reference Library" section.
- `devtools::check()`: 0 errors, 0 warnings, 2 notes (pre-existing).
