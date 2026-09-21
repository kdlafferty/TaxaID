# Functions written after code review

As of commit d4bded6 (2026-09-21), regenerated against the current tree and full git
history in this worktree.

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
conversion in this repo's history). Dates used (unchanged from the original derivation):
TaxaTools 2026-06-27, TaxaFetch 2026-07-09, TaxaMatch 2026-07-13, TaxaLikely 2026-07-30,
TaxaExpect 2026-07-31, TaxaHabitat 2026-08-03, TaxaAssign 2026-08-04, TaxaFlag 2026-08-07,
TaxaWizard 2026-08-09.

For each package's `R/` source, every top-level function definition (`name <- function(...)`
or `` `%op%` <- function(...) ``, at column 0) was extracted from the current working tree,
and its introduction date was found via `git log -S"name <- function"` (and the `=`-assignment
variant) restricted to the package's `R/` directory, taking the oldest matching commit date.
A function counts as "new" if that date is after the package's review-pulled date. Exported
status is taken from each package's current `NAMESPACE` (`export(...)` lines), not inferred
from the leading-dot naming convention alone, since a small number of unexported functions
do not follow that convention (e.g. `identify_confident_observations` in TaxaLikely, S3
methods such as `print.foo`).

Two additions to the original method, both requested for this pass:

1. **Renames.** A function whose current name has no git history of its own, but whose
   introducing commit is also a same-file/same-commit removal of a differently-named
   `<- function` definition (or whose introducing commit message explicitly says
   "renamed"/"moved"), is treated as reviewed under the old name rather than as new.
   Detected via `git log -S"<name> <- function"` plus inspection of the introducing
   commit's diff and message; cross-package moves were confirmed the same way. Any case
   found ambiguous is marked "possibly renamed, verify" rather than silently included or
   excluded. Only one confirmed case was found this pass (see TaxaLikely, below); no
   ambiguous ("verify") cases were found.
2. **Removed exports.** For each package, `NAMESPACE` at the commit nearest to (on or
   before) the review-pulled date was diffed against the current `NAMESPACE`. Names present
   in the old export list but absent from the current one are listed under "Removed since
   review" with the disposition found in git history (deleted outright, internalised
   without a leading dot, or moved to another package). These need no template review; any
   reviewer comments on them are moot.

## TaxaAssign
Review pulled: 2026-08-04

- .beta_mean (file: TaxaAssign/R/site_utils.R, introduced: 2026-08-09)
- .check_rank_system_order (file: TaxaAssign/R/site_utils.R, introduced: 2026-08-09)
- .find_consensus_by_agreement (file: TaxaAssign/R/score_consensus.R, introduced: 2026-09-12)
- .is_kernel_branch (file: TaxaAssign/R/kernel_branch.R, introduced: 2026-09-14)
- .rank_agreement_fraction (file: TaxaAssign/R/score_consensus.R, introduced: 2026-09-12)
- .rank_is_coarser_than (file: TaxaAssign/R/score_consensus.R, introduced: 2026-09-12)
- .row_col_or (file: TaxaAssign/R/posterior_consensus.R, introduced: 2026-08-09)

No new exported functions this pass; all 7 new functions are internal.

Removed since review:
- expand_unreferenced_hypotheses -- deleted from TaxaAssign at commit 606ecba ("TaxaAssign:
  second code + domain review response, expand_unreferenced_hypotheses removed"); a
  same-named function already lived in TaxaLikely since 2026-07-11 and is the surviving one
  (`TaxaLikely::expand_unreferenced_hypotheses()`, unaffected by this pass since it predates
  TaxaLikely's own 2026-07-30 review pull).
- suggest_unreferenced_species -- present in TaxaAssign since 2026-05-20 (i.e. reviewed
  under TaxaAssign well before the 2026-08-04 pull); moved wholesale to TaxaLikely at commit
  ad97447 ("package-placement fix"), forwarding wrapper left behind in TaxaAssign and later
  deleted at commit e29abab (2026-09-20). See TaxaLikely note below -- not counted as new
  there.

## TaxaExpect
Review pulled: 2026-07-31

- .beta_mean (file: TaxaExpect/R/utils_internal.R, introduced: 2026-08-04)
- .beta_sd (file: TaxaExpect/R/utils_internal.R, introduced: 2026-08-04)
- .empty_undetected_evidence_result (file: TaxaExpect/R/apply_undetected_evidence.R, introduced: 2026-08-26)
- .resolve_evidence_groups (file: TaxaExpect/R/apply_undetected_evidence.R, introduced: 2026-09-04)
- .resolve_gbif_taxon_key (file: TaxaExpect/R/generate_regional_proximity_evidence.R, introduced: 2026-08-26)
- .resolve_gbif_taxon_keys_batch (file: TaxaExpect/R/generate_regional_proximity_evidence.R, introduced: 2026-08-26)
- .resolve_group_prices (file: TaxaExpect/R/apply_undetected_evidence.R, introduced: 2026-09-04)
- .theta_surface_accumulate (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_apply_mask (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_axis (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_bbox (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_bin_index (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_condition_label (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-03)
- .theta_surface_downsample (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_downsample_matrix (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_engine (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_fft_convolve (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_fft_convolve_batch (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_in_polygon (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_kernel (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_plot_leaflet (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_plot_static (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_raster (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- .theta_surface_wkt_to_polys (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-02)
- apply_undetected_evidence (file: TaxaExpect/R/apply_undetected_evidence.R, introduced: 2026-08-26)
- calibrate_kernel_bandwidth (file: TaxaExpect/R/calibrate_kernel_bandwidth.R, introduced: 2026-08-30)
- condition_evidence_on_habitat (file: TaxaExpect/R/condition_evidence_on_habitat.R, introduced: 2026-09-12)
- estimate_kernel_priors (file: TaxaExpect/R/estimate_kernel_priors.R, introduced: 2026-08-30)
- fit_regional_presence_curve (file: TaxaExpect/R/fit_regional_presence_curve.R, introduced: 2026-08-28)
- generate_inat_range_evidence (file: TaxaExpect/R/generate_inat_range_evidence.R, introduced: 2026-08-28)
- generate_invasive_watch_evidence (file: TaxaExpect/R/generate_invasive_watch_evidence.R, introduced: 2026-08-26)
- generate_presence_curve_evidence (file: TaxaExpect/R/generate_presence_curve_evidence.R, introduced: 2026-08-31)
- generate_regional_proximity_evidence (file: TaxaExpect/R/generate_regional_proximity_evidence.R, introduced: 2026-08-26)
- generate_uncertain_habitat_evidence (file: TaxaExpect/R/generate_uncertain_habitat_evidence.R, introduced: 2026-09-19)
- generate_user_specified_evidence (file: TaxaExpect/R/generate_presence_curve_evidence.R, introduced: 2026-08-31)
- kernel_budget_sensitivity (file: TaxaExpect/R/kernel_budget_sensitivity.R, introduced: 2026-09-03)
- plot_theta_surface (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)
- print.taxaexpect_kernel_budget_sensitivity (file: TaxaExpect/R/kernel_budget_sensitivity.R, introduced: 2026-09-03)
- print.taxaexpect_kernel_priors (file: TaxaExpect/R/estimate_kernel_priors.R, introduced: 2026-08-30)
- print.taxaexpect_theta_surface (file: TaxaExpect/R/plot_theta_surface.R, introduced: 2026-09-01)

Removed since review (13, all archived at commit ad97447, "Ecosystem-wide function
retirement sweep"): add_pca_covariates, apply_pca_transform, build_priors,
compute_adaptive_sampling_groups, compute_moran_basis, create_sites_from_grid,
generate_full_priors, optimize_grid_size, plot_theta_map_interactive,
prepare_model_dataframe, screen_spatial_formula, train_biodiversity_model,
train_biodiversity_model_by_group -- the grid/GLMM prior-fitting chain, superseded
ecosystem-wide by the kernel-based estimator (`estimate_kernel_priors()` etc., above).
plot_theta_map_interactive is functionally succeeded by the new plot_theta_surface() (KDE
prior-field map) but is not a rename -- different implementation, kept in the "new" list.

## TaxaFetch
Review pulled: 2026-07-09

- .axis_or_default (file: TaxaFetch/R/pdf_extract.R, introduced: 2026-08-09)
- .detect_attr_col (file: TaxaFetch/R/dataone_eml_screen.R, introduced: 2026-08-09)
- .gbif_clear_pending_key (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-13)
- .gbif_declared_size (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-05)
- .gbif_default_year_range (file: TaxaFetch/R/fetch_gbif_occurrences.R, introduced: 2026-08-09)
- .gbif_download_consent (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-05)
- .gbif_record_pending_key (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-11)
- .gbif_submit_with_retry (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-10)
- .gbif_transient_error (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-10)
- .gbif_wait_with_retry (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-11)
- .gbif_zip_intact (file: TaxaFetch/R/download_gbif_occurrences.R, introduced: 2026-09-05)
- .inat_observation_count (file: TaxaFetch/R/fetch_inat_occurrences.R, introduced: 2026-07-28)
- .nearest_institution (file: TaxaFetch/R/filter_gbif_quality.R, introduced: 2026-07-28)
- .render_one_page_b64 (file: TaxaFetch/R/pdf_api.R, introduced: 2026-08-09)
- .taxafetch_is_zip_like (file: TaxaFetch/R/taxafetch_clear_cache.R, introduced: 2026-09-14)
- .taxafetch_referenced_zips (file: TaxaFetch/R/taxafetch_clear_cache.R, introduced: 2026-09-03)
- .track_removed (file: TaxaFetch/R/filter_gbif_quality.R, introduced: 2026-07-28)
- check_geographic_outliers (file: TaxaFetch/R/check_geographic_outliers.R, introduced: 2026-07-20)
- dedupe_occurrences (file: TaxaFetch/R/dedupe_occurrences.R, introduced: 2026-07-28)
- fetch_inat_occurrences (file: TaxaFetch/R/fetch_inat_occurrences.R, introduced: 2026-07-28)
- taxafetch_clear_cache (file: TaxaFetch/R/taxafetch_clear_cache.R, introduced: 2026-09-03)

Removed since review:
- fetch_dataone_eml -- removed in the A7 export cleanup (commit d6cda80 and surrounding
  "TaxaFetch A7" commits regenerated NAMESPACE/man after export changes).
- fetch_occurrences_by_taxon -- removed alongside build_taxon_screen_prompt() and
  parse_taxon_screening_response() at commit f100524 ("TaxaFetch A7: remove
  build_taxon_screen_prompt, parse_taxon_screening_response, fetch_occurrences_by_taxon").

## TaxaFlag
Review pulled: 2026-08-07

- .build_spatial_context_server (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- .check_gbif_tile_range_at_zoom (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .dilate8 (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .fetch_gbif_tile_alpha (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .fetch_inat_points (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- .fmt_pipeline_value (file: TaxaFlag/R/review_assignments.R, introduced: 2026-09-07)
- .gbif_legend_swatch (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- .gbif_tile_url (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- .grow_patch_size (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .haversine_km (file: TaxaFlag/R/compute_local_occurrence_distance.R, introduced: 2026-08-08)
- .is_unreviewed_row (file: TaxaFlag/R/review_assignments.R, introduced: 2026-09-14)
- .lonlat_to_tile_pixel (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .mercator_resolution_km (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- .parse_json_text (file: TaxaFlag/R/review_assignments.R, introduced: 2026-09-07)
- .rbind_reviews (file: TaxaFlag/R/review_assignments.R, introduced: 2026-09-14)
- .resolve_gbif_taxon_key (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- .review_cache_hash (file: TaxaFlag/R/taxaflag_clear_cache.R, introduced: 2026-09-04)
- .review_cache_read (file: TaxaFlag/R/taxaflag_clear_cache.R, introduced: 2026-09-04)
- .review_cache_write (file: TaxaFlag/R/taxaflag_clear_cache.R, introduced: 2026-09-04)
- .review_spatial_context_impl (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- .summarise_spatial_context (file: TaxaFlag/R/review_assignments.R, introduced: 2026-08-08)
- .tile_cache_key (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-09-13)
- .tile_cache_read (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-09-13)
- .tile_cache_write (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-09-13)
- check_gbif_tile_range (file: TaxaFlag/R/check_gbif_tile_range.R, introduced: 2026-08-08)
- compute_local_occurrence_distance (file: TaxaFlag/R/compute_local_occurrence_distance.R, introduced: 2026-08-08)
- flag_watch_candidates (file: TaxaFlag/R/flag_watch_candidates.R, introduced: 2026-08-28)
- review_spatial_context (file: TaxaFlag/R/review_spatial_context.R, introduced: 2026-08-08)
- taxaflag_clear_cache (file: TaxaFlag/R/taxaflag_clear_cache.R, introduced: 2026-09-04)
- validate_controls (file: TaxaFlag/R/validate_controls.R, introduced: 2026-09-20)

(Note carried from the previous version of this doc: the first 17 land on the single day
immediately after the stated review date -- consistent with these being written as part of
the same review-response session that produced the 2026-08-08 commit, but after the
reviewer's Aug-7 read of the code.)

Removed since review:
- build_review_covariates -- removed at commit 345b76f ("A7: remove
  build_review_covariates() from TaxaFlag"); its site-breadth functionality now lives as
  arguments on flag_contaminant() and validate_controls() directly (evidence gate,
  direction, and site breadth -- commits d7031c2 and 6002155) rather than as a standalone
  export.

## TaxaHabitat
Review pulled: 2026-08-03

- .bulk_gate_decision (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .candidate_habitat_cols (file: TaxaHabitat/R/report_habitat.R, introduced: 2026-09-10)
- .candidate_habitats (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .check_bulk_args (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .check_habitat_sentinel_free (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-19)
- .compute_habitat_breadth (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .habitat_admissible (file: TaxaHabitat/R/resolve_habitat_geography.R, introduced: 2026-09-19)
- .habitat_cache_hash (file: TaxaHabitat/R/build_habitat_lookup.R, introduced: 2026-09-10)
- .habitat_cache_read (file: TaxaHabitat/R/build_habitat_lookup.R, introduced: 2026-09-10)
- .habitat_cache_write (file: TaxaHabitat/R/build_habitat_lookup.R, introduced: 2026-09-10)
- .habitat_choice_html (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-19)
- .habitat_signature (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .habitat_view_counts (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-19)
- .is_habitat_unassigned (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-19)
- .looks_like_habitat_weights (file: TaxaHabitat/R/report_habitat.R, introduced: 2026-09-10)
- .mercator_y (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .points_in_polygon (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .resolve_taxon_col (file: TaxaHabitat/R/report_habitat.R, introduced: 2026-09-10)
- .summarise_habitat_weights (file: TaxaHabitat/R/report_habitat.R, introduced: 2026-09-10)
- .summarise_main_habitat (file: TaxaHabitat/R/report_habitat.R, introduced: 2026-09-10)
- .undo_group_state (file: TaxaHabitat/R/utils_plot.R, introduced: 2026-09-18)
- .utm_crs_for (file: TaxaHabitat/R/utils_utm.R, introduced: 2026-09-15)
- apply_spatial_review_decisions (file: TaxaHabitat/R/spatial_review_decisions.R, introduced: 2026-09-12)
- build_habitat_lookup (file: TaxaHabitat/R/build_habitat_lookup.R, introduced: 2026-09-10)
- resolve_habitat_by_geography (file: TaxaHabitat/R/resolve_habitat_geography.R, introduced: 2026-09-19)
- save_spatial_review_decisions (file: TaxaHabitat/R/spatial_review_decisions.R, introduced: 2026-09-12)
- taxahabitat_clear_cache (file: TaxaHabitat/R/build_habitat_lookup.R, introduced: 2026-09-10)

No removed exports since review (the original "no new functions found" verdict for this
package no longer holds -- 27 functions have landed since 2026-08-03, entirely absent from
the earlier version of this doc).

## TaxaLikely
Review pulled: 2026-07-30

- .align_pairs_by_genus (file: TaxaLikely/R/build_sequence.R, introduced: 2026-09-07)
- .audit_barcode_coverage_impl (file: TaxaLikely/R/coverage.R, introduced: 2026-08-09)
- .bimodality_check (file: TaxaLikely/R/bimodality.R, introduced: 2026-09-13)
- .check_pair_coverage_floor (file: TaxaLikely/R/evaluate.R, introduced: 2026-09-10)
- .check_score_ratio_monotonicity (file: TaxaLikely/R/train.R, introduced: 2026-08-09)
- .decipher_align_pairs (file: TaxaLikely/R/build_sequence.R, introduced: 2026-09-07)
- .empty_reference_df (file: TaxaLikely/R/fetch.R, introduced: 2026-09-02)
- .estimate_score_quantum (file: TaxaLikely/R/bimodality.R, introduced: 2026-09-14)
- .fasta_cache_keys (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .fetch_fasta_cached (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .fit_two_component_normal (file: TaxaLikely/R/bimodality.R, introduced: 2026-09-13)
- .format_id_list (file: TaxaLikely/R/evaluate.R, introduced: 2026-09-10)
- .mixture_has_valley (file: TaxaLikely/R/bimodality.R, introduced: 2026-09-13)
- .ref_cache_evict (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .ref_cache_file (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .ref_cache_grammar (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .ref_cache_stem (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .ref_cache_stem_of (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .ref_cache_unreachable (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .sel_params (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .sel_params_status (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- .smooth_comb (file: TaxaLikely/R/bimodality.R, introduced: 2026-09-14)
- .with_count_failures (file: TaxaLikely/R/fetch.R, introduced: 2026-09-14)
- check_cross_genus_sampling_noise (file: TaxaLikely/R/build_sequence.R, introduced: 2026-09-07)
- taxalikely_clear_cache (file: TaxaLikely/R/taxalikely_clear_cache.R, introduced: 2026-09-03)

Not counted as new (confirmed cross-package move, not fresh work): suggest_unreferenced_species
and its 9 internal helpers (TaxaLikely/R/suggest_unreferenced_species.R -- .build_context_block,
.build_family_prompt, .build_plausible_prompt, .count_barcode_seqs,
.new_unreferenced_species_result, .parse_family_response, .parse_plausible_response,
.resolve_llm_fn, print.unreferenced_species_result) mechanically date to 2026-09-10 in
TaxaLikely's history, but the exported function itself is the same code that lived in
TaxaAssign since 2026-05-20 and was reviewed there before TaxaAssign's 2026-08-04 pull; it
was moved to TaxaLikely at commit ad97447 as a package-placement fix. Treated as already
reviewed.

Removed since review:
- flag_reference_errors, remove_flagged_references -- retired at commit ad97447,
  superseded by TaxaMatch::corroborate_references_locally() + TaxaMatch::evaluate_reference_accessions().
  (A response-file passage records remove_flagged_references.R as itself a rename target
  of an earlier clean.R -- see the TaxaLikely response file; that mapping predates and is
  independent of this later retirement.)
- build_site_reference, calibrate_coverage_filter, coverage_threshold, compute_likelihoods,
  model_likelihoods -- archived at commit ad97447 as zero-real-caller ecosystem-wide (the
  coverage-filter pair after a real A/B test quantified its accuracy/coverage tradeoff;
  opt-in only, never shipped as a default).
- identify_confident_observations -- not deleted, internalised: commit 4fa99b3 ("A7:
  internalise identify_confident_observations() in TaxaLikely") dropped it from NAMESPACE
  but the function still exists (TaxaLikely/R/calibrate_query_noise.R, called internally by
  train_likelihood_model()). No leading dot despite being unexported -- pre-existing naming
  inconsistency, not introduced by this pass.

## TaxaMatch
Review pulled: 2026-07-13

- .accession_review_fingerprint (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-14)
- .align_to_cache_columns (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-03)
- .apply_local_veto (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-03)
- .apply_top_n (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .attach_taxonomy (file: TaxaMatch/R/blast_sequences.R, introduced: 2026-08-03)
- .blast_against_comparison_set (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .blast_rate_limit_sleep (file: TaxaMatch/R/blast_sequences.R, introduced: 2026-08-14)
- .blast_server_rejected (file: TaxaMatch/R/blast_sequences.R, introduced: 2026-08-09)
- .build_accession_review_prompt (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-13)
- .build_core_seq_df (file: TaxaMatch/R/sequence_input.R, introduced: 2026-07-20)
- .build_params_key (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-03)
- .build_submission_batch_lookup (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .check_col_exists (file: TaxaMatch/R/standardize_match_data.R, introduced: 2026-07-20)
- .check_pkg (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .check_rename_safe (file: TaxaMatch/R/standardize_match_data.R, introduced: 2026-07-20)
- .compute_hierarchy_congruence (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .default_params_key (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-03)
- .empty_acc_taxonomy_result (file: TaxaMatch/R/blast_sequences.R, introduced: 2026-07-20)
- .empty_animl_result (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-20)
- .empty_birdnet_result (file: TaxaMatch/R/read_birdnet_output.R, introduced: 2026-07-20)
- .empty_inat_result (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-20)
- .empty_reference_pair_cache (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-02)
- .empty_speciesnet_result (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-28)
- .evaluate_reference_accessions_chunk (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-14)
- .extract_amplicon_one_tm (file: TaxaMatch/R/trim_query_to_amplicon.R, introduced: 2026-08-09)
- .extract_feature_table_fallback (file: TaxaMatch/R/trim_query_to_amplicon.R, introduced: 2026-09-01)
- .extract_genus (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .fetch_marker_annotation (file: TaxaMatch/R/check_marker_mismatch.R, introduced: 2026-08-09)
- .fetch_reference_accession_records (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .filter_and_cap_accessions (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .fmt_time (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .generate_asv_ids (file: TaxaMatch/R/sequence_input.R, introduced: 2026-07-20)
- .get_species_comparison_meta (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .investigate_flagged_accession_core (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .investigate_params_key (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .investigate_verdict (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .label_confidence_from_evidence (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-02)
- .load_accession_review_cache (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-14)
- .load_investigate_cache (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .load_reference_accession_cache (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .load_reference_pair_cache (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-02)
- .local_corroboration_columns (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-03)
- .looks_like_counts (file: TaxaMatch/R/sequence_input.R, introduced: 2026-09-18)
- .lookup_investigate_cache (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .na_like (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-04)
- .normalize_sites_defaults (file: TaxaMatch/R/group_observations_by_bbox.R, introduced: 2026-09-20)
- .parse_accession_review_response (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-13)
- .parse_create_date (file: TaxaMatch/R/local_corroboration.R, introduced: 2026-09-03)
- .parse_speciesnet_label (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-28)
- .parse_speciesnet_predictions (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-28)
- .partner_trust_weight (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-02)
- .print_investigation_summary (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .recover_truncated_accession_json (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-13)
- .reference_action_from_confidence (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-02)
- .resolve_expected_marker (file: TaxaMatch/R/trim_query_to_amplicon.R, introduced: 2026-09-01)
- .resolve_label_params (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-02)
- .resolve_marker_pattern (file: TaxaMatch/R/check_marker_mismatch.R, introduced: 2026-08-09)
- .resolve_trimmed_span_max (file: TaxaMatch/R/trim_query_to_amplicon.R, introduced: 2026-09-02)
- .review_accession_batch_with_retry (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-13)
- .same_submission_batch (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .save_accession_review_cache (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-14)
- .save_investigate_cache (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .save_reference_accession_cache (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- .save_reference_pair_cache (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-02)
- .search_species_accessions (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .speciesnet_detection_coverage (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-28)
- .split_batches_by_length (file: TaxaMatch/R/blast_sequences.R, introduced: 2026-09-01)
- .stop_missing_files (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .store_investigate_result (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .strip_acc_version (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-09-03)
- .summarise_corroborators (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-04)
- .trim_queries_to_amplicon (file: TaxaMatch/R/trim_query_to_amplicon.R, introduced: 2026-08-09)
- .valid_reference_length (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- .validate_min_conf_top_n (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .validate_rank_system (file: TaxaMatch/R/standardize_match_data.R, introduced: 2026-07-20)
- .warn_duplicate_basenames (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- .warn_na_coercion (file: TaxaMatch/R/utils_shared.R, introduced: 2026-07-20)
- check_marker_mismatch (file: TaxaMatch/R/check_marker_mismatch.R, introduced: 2026-08-09)
- corroborate_references_locally (file: TaxaMatch/R/local_corroboration.R, introduced: 2026-09-03)
- evaluate_reference_accessions (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- flag_incongruent_references (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- investigate_flagged_accession (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- investigate_flagged_accessions (file: TaxaMatch/R/investigate_flagged_accession.R, introduced: 2026-08-09)
- match_driving_accessions (file: TaxaMatch/R/local_corroboration.R, introduced: 2026-09-03)
- read_speciesnet_output (file: TaxaMatch/R/read_image_classifiers.R, introduced: 2026-07-28)
- refine_reference_verdicts (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-02)
- remove_incongruent_references (file: TaxaMatch/R/evaluate_reference_accessions.R, introduced: 2026-08-09)
- resolve_review_overrides (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-30)
- review_flagged_accessions (file: TaxaMatch/R/review_flagged_accessions.R, introduced: 2026-08-13)
- score_reference_labels (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-02)
- verify_local_corroborations (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-07)
- verify_removal_candidates (file: TaxaMatch/R/reference_label_verdict.R, introduced: 2026-09-04)

(Note carried from the previous version of this doc: TaxaMatch's review is the oldest of
the nine relative to today, which largely explains the long list -- most of this package's
active development has landed since. `.apply_top_n` through `.warn_na_coercion` at
2026-07-20 came from the `utils_shared.R` consolidation; the reference-verification clusters
(`evaluate_reference_accessions.R`, `investigate_flagged_accession.R`,
`check_marker_mismatch.R`, `local_corroboration.R`, `reference_label_verdict.R`,
`review_flagged_accessions.R`) are newer, distinct feature additions, and none of them
existed under any other name at review time -- `verify_flagged_references()`, the function
their commit history says they supersede, was itself introduced after the 2026-07-13 review
pull (commit 78c8eb2) and retired before ever being reviewed, so it needs no rename mapping.)

Removed since review:
- read_wildlife_insights_output -- removed 2026-07-23 when SpeciesNet ingestion was added
  and the Wildlife Insights reader retired.

## TaxaTools
Review pulled: 2026-06-27

- .common_name_cache_key (file: TaxaTools/R/common_names.R, introduced: 2026-09-12)
- .common_name_cache_path (file: TaxaTools/R/common_names.R, introduced: 2026-09-12)
- .harmonise_taxonomy_to_backbone (file: TaxaTools/R/sampling_group.R, introduced: 2026-09-13)
- .last_classification_rank (file: TaxaTools/R/verify_taxon_names.R, introduced: 2026-07-28)
- .pts_to_wkt (file: TaxaTools/R/define_search_polygon.R, introduced: 2026-07-04)
- .read_common_name_cache (file: TaxaTools/R/common_names.R, introduced: 2026-09-12)
- .read_worms_cache (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .taxaid_code_hash (file: TaxaTools/R/build_manifest.R, introduced: 2026-09-18)
- .trunc_label (file: TaxaTools/R/cache_utils.R, introduced: 2026-09-14)
- .warn_possible_backbone_mismatch (file: TaxaTools/R/sampling_group.R, introduced: 2026-09-13)
- .wkt_to_pts (file: TaxaTools/R/define_search_polygon.R, introduced: 2026-07-04)
- .worms_cache_key (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_cache_path (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_chr (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_empty_row (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_finalise (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_flag (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_get (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_int (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_match_names (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_ncbi_id (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_row_from_records (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .worms_wrims (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- .write_common_name_cache (file: TaxaTools/R/common_names.R, introduced: 2026-09-12)
- .write_worms_cache (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- assign_sampling_group (file: TaxaTools/R/sampling_group.R, introduced: 2026-09-13)
- cache_ok (file: TaxaTools/R/cache_utils.R, introduced: 2026-09-14)
- check_taxaid_manifest (file: TaxaTools/R/build_manifest.R, introduced: 2026-09-18)
- default_sampling_scheme (file: TaxaTools/R/sampling_group.R, introduced: 2026-09-13)
- define_search_polygon (file: TaxaTools/R/define_search_polygon.R, introduced: 2026-07-04)
- escalate_taxonomic_rank (file: TaxaTools/R/escalate_taxonomic_rank.R, introduced: 2026-07-05)
- fetch_worms_attributes (file: TaxaTools/R/worms_attributes.R, introduced: 2026-09-15)
- list_cache_files (file: TaxaTools/R/cache_utils.R, introduced: 2026-09-03)
- report_and_clear_cache (file: TaxaTools/R/cache_utils.R, introduced: 2026-09-03)
- resolve_barcode_marker (file: TaxaTools/R/barcode_utils.R, introduced: 2026-09-02)
- resolve_barcode_primers (file: TaxaTools/R/barcode_utils.R, introduced: 2026-07-06)
- taxaid_build_manifest (file: TaxaTools/R/build_manifest.R, introduced: 2026-09-18)
- taxaid_cache_report (file: TaxaTools/R/cache_utils.R, introduced: 2026-09-14)
- taxatools_clear_cache (file: TaxaTools/R/common_names.R, introduced: 2026-09-12)
- write_taxaid_manifest (file: TaxaTools/R/build_manifest.R, introduced: 2026-09-18)

No removed exports since review.

## TaxaWizard
Review pulled: 2026-08-09

- .bare_exists_in_base (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .build_fallback_snippet_block (file: TaxaWizard/R/graph.R, introduced: 2026-09-18)
- .build_function_entry (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .build_package_registry (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .call_fn_name (file: TaxaWizard/R/shiny.R, introduced: 2026-08-11)
- .check_cache (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .check_packages (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .check_r (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .check_row (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .clean_rd_text (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .collect_local_functions (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .confirm_yes (file: TaxaWizard/R/shiny.R, introduced: 2026-08-11)
- .detect_paths_in_text (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .env_is_set (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .first_paragraph (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .format_check_block (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .format_registry_signature (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .format_sniff_block (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .in_renviron (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .keep_known_edges (file: TaxaWizard/R/output.R, introduced: 2026-09-18)
- .load_requirements (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .looks_like_dna (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .net_reachable (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .pack_agent_note (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_context_package_md (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_context_taxaid_md (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_find_repo_root (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_graph_adjacency_text (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_packages_table (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_params_table (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_pipeline_awareness_text (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_read_quick_start (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_read_template (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_render_task (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_requirements_summary (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_requirements_table (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_setup_report_md (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_strip_json_format (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .pack_task_bracket_map (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- .parse_rd_txt (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .peek_lines (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .pkg_row (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .r_string (file: TaxaWizard/R/output.R, introduced: 2026-09-07)
- .rd_alias_map (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .rd_arguments (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .rd_sections (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .rd_text (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .rd_text_parts (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .registry_cache_dir (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .registry_docs (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)
- .registry_fn_index (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .resolve_bin_token (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .resolve_call_head (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .resolve_key_token (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .resolve_net_token (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .resolve_pkg_token (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .rows_to_df (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .selected_requires_tokens (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .session_setup_check (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .sniff_dir (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .sniff_file (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .sniff_header_row (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .truncate_at_word (file: TaxaWizard/R/registry.R, introduced: 2026-09-20)
- .tw_trunc (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- .validate_one_call (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .validate_one_snippet (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .validate_rows_to_df (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .validate_snippets (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .validate_stale_argument (file: TaxaWizard/R/validate.R, introduced: 2026-09-18)
- .widen_step0_edges (file: TaxaWizard/R/output.R, introduced: 2026-09-18)
- .widen_workflow_params (file: TaxaWizard/R/output.R, introduced: 2026-09-19)
- print.taxaid_check (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- sniff_input (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- workflow_check (file: TaxaWizard/R/setup.R, introduced: 2026-09-18)
- workflow_export_prompts (file: TaxaWizard/R/pack.R, introduced: 2026-09-18)
- workflow_registry (file: TaxaWizard/R/registry.R, introduced: 2026-09-18)

(.call_fn_name and .confirm_yes were flagged "UNCOMMITTED" in the 2026-08-11 version of
this doc; both were committed at 2026-08-11 in TaxaWizard/R/shiny.R and are included above
with that date.)

Removed since review:
- workflow_chat, workflow_gadget -- removed directly as part of the human reviewer's own
  review response (commit message: "Micah Wright review response: workflow_chat()/
  workflow_gadget() removed"). Already addressed in the response file; listed here for
  completeness only.
