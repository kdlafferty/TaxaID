# TaxaMatch Session Notes Archive
# Sessions 27–82. Current sessions live in TaxaMatch/CLAUDE.md.

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
