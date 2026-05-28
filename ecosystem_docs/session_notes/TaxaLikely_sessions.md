# TaxaLikely Session Notes Archive
# Sessions 30–88. Current sessions (90+) live in TaxaLikely/CLAUDE.md.

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
