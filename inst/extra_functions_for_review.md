# Functions written after code review

Methodology: for each package, the "review pulled" date is the date the reviewer
actually read the codebase, taken preferentially from an explicit `Review date: YYYY-MM-DD`
statement embedded in the package's `inst/<pkg>_review.Rmd` (present in the
Claude-authored review draft that was later reformatted into the standard human-reviewer
checklist template used ecosystem-wide; the reformatting commits are documented as
"no code changes -- doc-only replacement" and are not a second read of the code, so the
earlier explicit date is used). Where no explicit date was ever present in any version of
the review doc, the git commit date that first introduced the review document's content
is used instead (`git log --name-status`, with git's rename detection resolved by hand
where `--follow` produced false matches against an earlier submodule-to-directory
conversion in this repo's history).

For each package's `R/` source, every top-level function definition (`name <- function(...)`
or `` `%op%` <- function(...) ``, at column 0) was extracted from the current working tree,
and its introduction date was found via `git log -S"name <- function"` (and the `=`-assignment
variant) restricted to the package's `R/` directory, taking the oldest matching commit date.
A function counts as "new" if that date is after the package's review-pulled date, or if the
function has no commit history at all (i.e. it exists only in an uncommitted working-tree
change as of 2026-08-11).

## TaxaAssign
Review pulled: 2026-08-04 (method: explicit "Review date: 2026-08-04" stated in the
Claude-authored review draft, commit c7c5d27, later reformatted into the current
human-checklist template at commit 606ecba on 2026-08-09 with no further code re-read)

- .beta_mean (file: R/site_utils.R, introduced: 2026-08-09)
- .check_rank_system_order (file: R/site_utils.R, introduced: 2026-08-09)
- .row_col_or (file: R/posterior_consensus.R, introduced: 2026-08-09)

## TaxaExpect
Review pulled: 2026-07-31 (method: explicit "Review date: 2026-07-31" stated in the
Claude-authored review draft, commit 45a643e, later reformatted into the current
human-authored review at commit 219d6ec on 2026-08-09 with no further code re-read --
commit message states "No code changes -- doc-only replacement")

- .beta_mean (file: R/utils_internal.R, introduced: 2026-08-04)
- .beta_sd (file: R/utils_internal.R, introduced: 2026-08-04)
- .parse_grid_id_coords (file: R/utils_internal.R, introduced: 2026-08-04)
- .prepare_one_group (file: R/prepare_model_dataframe.R, introduced: 2026-08-04)

## TaxaFetch
Review pulled: 2026-07-09 (method: explicit "Review date: 2026-07-09" stated in the
Claude-authored review draft, matches the original commit f10de2d ("Session 148: TaxaFetch
code and domain review") the same day; later reformatted into the current human-authored
review at commit 5ac1599 on 2026-08-09 with no further code re-read)

- .axis_or_default (file: R/pdf_extract.R, introduced: 2026-08-09)
- .detect_attr_col (file: R/dataone_eml_screen.R, introduced: 2026-08-09)
- .gbif_default_year_range (file: R/fetch_gbif_occurrences.R, introduced: 2026-08-09)
- .inat_observation_count (file: R/fetch_inat_occurrences.R, introduced: 2026-07-28)
- .nearest_institution (file: R/filter_gbif_quality.R, introduced: 2026-07-28)
- .render_one_page_b64 (file: R/pdf_api.R, introduced: 2026-08-09)
- .track_removed (file: R/filter_gbif_quality.R, introduced: 2026-07-28)
- check_geographic_outliers (file: R/check_geographic_outliers.R, introduced: 2026-07-20)
- dedupe_occurrences (file: R/dedupe_occurrences.R, introduced: 2026-07-28)
- fetch_inat_occurrences (file: R/fetch_inat_occurrences.R, introduced: 2026-07-28)

## TaxaFlag
Review pulled: 2026-08-07 (method: explicit "Review date: 2026-08-07" stated in the review
doc; committed the following day at commit 7c00717 (2026-08-08). NOTE: at the time of this
audit (2026-08-11) the working tree has an *uncommitted* edit that reformats this same file
into the ecosystem's standard human-checklist template -- the explicit-date text is only
present in the last-committed version, but that version's text is what was used here per
the stated priority order)

- .build_spatial_context_server (file: R/review_spatial_context.R, introduced: 2026-08-08)
- .check_gbif_tile_range_at_zoom (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .dilate8 (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .fetch_gbif_tile_alpha (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .fetch_inat_points (file: R/review_spatial_context.R, introduced: 2026-08-08)
- .gbif_legend_swatch (file: R/review_spatial_context.R, introduced: 2026-08-08)
- .gbif_tile_url (file: R/review_spatial_context.R, introduced: 2026-08-08)
- .grow_patch_size (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .haversine_km (file: R/compute_local_occurrence_distance.R, introduced: 2026-08-08)
- .lonlat_to_tile_pixel (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .mercator_resolution_km (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .resolve_gbif_taxon_key (file: R/review_spatial_context.R, introduced: 2026-08-08)
- .review_spatial_context_impl (file: R/review_spatial_context.R, introduced: 2026-08-08)
- .summarise_spatial_context (file: R/review_assignments.R, introduced: 2026-08-08)
- check_gbif_tile_range (file: R/check_gbif_tile_range.R, introduced: 2026-08-08)
- compute_local_occurrence_distance (file: R/compute_local_occurrence_distance.R, introduced: 2026-08-08)
- review_spatial_context (file: R/review_spatial_context.R, introduced: 2026-08-08)

(Note: all 17 land on the single day immediately after the stated review date -- consistent
with these being written as part of the same review-response session that produced the
2026-08-08 commit, but after the reviewer's Aug-7 read of the code. Flagged here as a
same-session, low-margin case worth a second look rather than a clear-cut gap.)

## TaxaHabitat
Review pulled: 2026-08-03 (method: git log first-add of the review doc's only-ever content,
commit 2cae3e7; no explicit date is stated in the document itself, and no version of it was
ever a separate Claude-authored draft)

(no new functions found)

## TaxaLikely
Review pulled: 2026-07-30 (method: explicit "Review date: 2026-07-30" stated in the
Claude-authored review draft, commit 7040f00, same day; later reformatted into the current
human-authored review at commit c36206d on 2026-08-09 with no further code re-read)

- .audit_barcode_coverage_impl (file: R/coverage.R, introduced: 2026-08-09)
- .check_score_ratio_monotonicity (file: R/train.R, introduced: 2026-08-09)
- .compute_reference_qc_stats (file: R/train.R, introduced: 2026-08-09)

## TaxaMatch
Review pulled: 2026-07-13 (method: git log first-add of the review doc's content, originally
committed at repo path "USGS code reviews/taxamatch_review.Rmd" in commit 6c2d962, later a
pure 100%-similarity rename into TaxaMatch/inst/ at commit f117469 with no content change;
no explicit date is stated in the document itself)

- .apply_top_n (file: R/utils_shared.R, introduced: 2026-07-20)
- .attach_taxonomy (file: R/blast_sequences.R, introduced: 2026-08-03)
- .blast_against_comparison_set (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .blast_server_rejected (file: R/blast_sequences.R, introduced: 2026-08-09)
- .build_core_seq_df (file: R/sequence_input.R, introduced: 2026-07-20)
- .build_submission_batch_lookup (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .check_col_exists (file: R/standardize_match_data.R, introduced: 2026-07-20)
- .check_pkg (file: R/utils_shared.R, introduced: 2026-07-20)
- .check_rename_safe (file: R/standardize_match_data.R, introduced: 2026-07-20)
- .compute_hierarchy_congruence (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .empty_acc_taxonomy_result (file: R/blast_sequences.R, introduced: 2026-07-20)
- .empty_animl_result (file: R/read_image_classifiers.R, introduced: 2026-07-20)
- .empty_birdnet_result (file: R/read_birdnet_output.R, introduced: 2026-07-20)
- .empty_inat_result (file: R/read_image_classifiers.R, introduced: 2026-07-20)
- .empty_speciesnet_result (file: R/read_image_classifiers.R, introduced: 2026-07-28)
- .extract_amplicon_one_tm (file: R/trim_query_to_amplicon.R, introduced: 2026-08-09)
- .extract_genus (file: R/utils_shared.R, introduced: 2026-07-20)
- .fetch_marker_annotation (file: R/check_marker_mismatch.R, introduced: 2026-08-09)
- .fetch_reference_accession_records (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .filter_and_cap_accessions (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .fmt_time (file: R/utils_shared.R, introduced: 2026-07-20)
- .generate_asv_ids (file: R/sequence_input.R, introduced: 2026-07-20)
- .get_species_comparison_meta (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .investigate_flagged_accession_core (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .investigate_params_key (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .investigate_verdict (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .load_investigate_cache (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .load_reference_accession_cache (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .lookup_investigate_cache (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .parse_speciesnet_label (file: R/read_image_classifiers.R, introduced: 2026-07-28)
- .parse_speciesnet_predictions (file: R/read_image_classifiers.R, introduced: 2026-07-28)
- .print_investigation_summary (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .resolve_marker_pattern (file: R/check_marker_mismatch.R, introduced: 2026-08-09)
- .same_submission_batch (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .save_investigate_cache (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .save_reference_accession_cache (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .search_species_accessions (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .speciesnet_detection_coverage (file: R/read_image_classifiers.R, introduced: 2026-07-28)
- .stop_missing_files (file: R/utils_shared.R, introduced: 2026-07-20)
- .store_investigate_result (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .trim_queries_to_amplicon (file: R/trim_query_to_amplicon.R, introduced: 2026-08-09)
- .valid_reference_length (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .validate_min_conf_top_n (file: R/utils_shared.R, introduced: 2026-07-20)
- .validate_rank_system (file: R/standardize_match_data.R, introduced: 2026-07-20)
- .warn_duplicate_basenames (file: R/utils_shared.R, introduced: 2026-07-20)
- .warn_na_coercion (file: R/utils_shared.R, introduced: 2026-07-20)
- check_marker_mismatch (file: R/check_marker_mismatch.R, introduced: 2026-08-09)
- evaluate_reference_accessions (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- flag_incongruent_references (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- investigate_flagged_accession (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- investigate_flagged_accessions (file: R/investigate_flagged_accession.R, introduced: 2026-08-09)
- read_speciesnet_output (file: R/read_image_classifiers.R, introduced: 2026-07-28)
- remove_incongruent_references (file: R/evaluate_reference_accessions.R, introduced: 2026-08-09)

(Note: TaxaMatch's review is the oldest of the nine relative to today, ~4 weeks old, which
largely explains the long list -- most of this package's active development has landed
since. `.apply_top_n` through `.warn_na_coercion` at 2026-07-20 came from the
`utils_shared.R` consolidation mentioned in that package's own review-response commit
(f117469); the `investigate_flagged_accession.R` / `evaluate_reference_accessions.R` /
`check_marker_mismatch.R` clusters at 2026-08-09 are newer, distinct feature additions.)

## TaxaTools
Review pulled: 2026-06-27 (method: git log first-add of the review doc's only-ever content,
commit adb1b88 ("Session 122: peer-review response, is_plausible_binomial rename, debris
cleanup"); no explicit date is stated in the document itself, and it was later a pure
rename-only move into inst/ with no content change)

- .last_classification_rank (file: R/verify_taxon_names.R, introduced: 2026-07-28)
- .pts_to_wkt (file: R/define_search_polygon.R, introduced: 2026-07-04)
- .wkt_to_pts (file: R/define_search_polygon.R, introduced: 2026-07-04)
- define_search_polygon (file: R/define_search_polygon.R, introduced: 2026-07-04)
- escalate_taxonomic_rank (file: R/escalate_taxonomic_rank.R, introduced: 2026-07-05)
- resolve_barcode_primers (file: R/barcode_utils.R, introduced: 2026-07-06)

## TaxaWizard
Review pulled: 2026-08-09 (method: explicit "Review date: 2026-08-09" stated in the review
doc as committed at commit c6c8fc7 (the package's first and, at HEAD, only review commit).
NOTE: at the time of this audit (2026-08-11) the working tree has an *uncommitted* edit
that reformats this same file into the ecosystem's standard human-checklist template with
no code changes noted)

- .call_fn_name (file: R/shiny.R, introduced: UNCOMMITTED -- present only in the current
  working tree as of 2026-08-11, no commit yet exists that adds it)
- .confirm_yes (file: R/shiny.R, introduced: UNCOMMITTED -- present only in the current
  working tree as of 2026-08-11, no commit yet exists that adds it)
