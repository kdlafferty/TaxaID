# TaxaID Name Change History
# Full log of function, column, parameter, and file renames across the ecosystem.
# Archived from CLAUDE.md (Sessions 19–123, most recently Session 124). See CLAUDE.md for anything newer.

| Date | Old name | New name | Package | Type | Downstream impact |
|---|---|---|---|---|---|
| 2026-02-18 | `f_spellcheck_sci_names` | `verify_sci_names` | TaxaTools | function | None yet |
| 2026-02-18 | `spellchecked_names` | `matched_name` | TaxaTools | column | Check scripts |
| 2026-02-18 | `bestResult_classificationPath` | `classification_path` | TaxaTools | column | Check scripts |
| 2026-02-18 | `bestResult_classificationRanks` | `classification_ranks` | TaxaTools | column | Check scripts |
| 2026-02-27 | `integrate_local_sources` | `combine_occurrence_sources` | TaxaExpect | function | No callers yet |
| 2026-02-27 | `make_hierarchical_habitat_prompt` | `build_habitat_prompt` | TaxaExpect | function | Now returns S3 object |
| 2026-02-27 | `call_anthropic_api` | `prompt_anthropic_api` | TaxaExpect | function | Now takes `habitat_prompt` object |
| 2026-02-27 | `submit_manual` | `prompt_manual` | TaxaExpect | function | Now takes `habitat_prompt` object |
| 2026-02-27 | `make_habitat_prompt` | *(deleted)* | TaxaExpect | function | Flat pipeline removed |
| 2026-02-27 | `assign_habitat_llm` | *(deleted)* | TaxaExpect | function | Flat pipeline removed |
| 2026-02-27 | `parse_habitat_response` | *(deleted)* | TaxaExpect | function | Flat pipeline removed |
| 2026-02-27 | `plot_raw_habitat_points` | *(deleted)* | TaxaExpect | function | Superseded |
| 2026-02-28 | `removeShape` | `removeMarker` | TaxaExpect | internal | Fixed deselect bug |
| 2026-02-28 | `filter_gbif_quality` | `filter_gbif_quality` | TaxaExpect | param added | New `max_coord_uncertainty` arg |
| 2026-03-01 | `build_neighbor_graph` | *(deleted)* | TaxaExpect | function | Superseded |
| 2026-03-01 | `compute_species_amplitude` | *(deleted)* | TaxaExpect | function | Superseded |
| 2026-03-01 | `update_theta_local` | *(deleted)* | TaxaExpect | function | Superseded |
| 2026-03-01 | `calibrate_prior_cap` | *(deleted)* | TaxaExpect | function | Superseded |
| 2026-03-04 | `"ok"` flag value | `"likely"` | TaxaExpect | `spatial_flag` value | Update filter scripts |
| 2026-03-04 | `"suspect"` flag value | `"questionable"` | TaxaExpect | `spatial_flag` value | Update filter scripts |
| 2026-03-04 | `"likely_error"` flag value | `"unlikely"` | TaxaExpect | `spatial_flag` value | Update filter scripts |
| 2026-03-10 | `CLAUDE_CONTEXT.md` | `AI_CONTEXT.md` | Ecosystem | context file | — |
| 2026-03-26 | `AI_CONTEXT.md` | `CLAUDE.md` | Ecosystem | context file | Renamed for Claude Code auto-detection |
| 2026-03-26 | `ecosystem_docs/CLAUDE.md` | `TaxaID/CLAUDE.md` | Ecosystem | context file | Moved to parent dir for true auto-detection |
| 2026-03-13 | *(Session 19)* | TaxaExpect split → TaxaFetch | Ecosystem | package | TaxaFetch created |
| 2026-03-13 | `combine_occurrence_sources` | *(retired)* | TaxaExpect/TaxaFetch | function | Replaced by `rename_cols()` + `stack_occurrences()` |
| 2026-03-13 | *(new)* | `rename_cols()` | TaxaTools | function | General DwC column rename utility |
| 2026-03-13 | *(new)* | `stack_occurrences()` | TaxaFetch | function | Row-bind occurrence frames |
| 2026-03-14 | *(Session 20)* | Weighted multi-habitat pipeline | TaxaFetch | breaking change | Wide weighted output replaces long format |
| 2026-03-15 | *(Session 21)* | Habitat scheme pipeline redesign | TaxaFetch | breaking change | NULL default → 3-category |
| 2026-03-24 | `prompt_anthropic_api` | `prompt_api` | TaxaFetch | function | All workflow scripts updated Session 26 |
| 2026-03-24 | *(Session 26 — new)* | `call_gemini_api()` | TaxaFetch | function | Google Gemini provider |
| 2026-03-24 | *(Session 26 — new)* | `call_openai_api()` | TaxaFetch | function | OpenAI provider |
| 2026-03-24 | *(Session 26 — new)* | `call_ollama_api()` | TaxaFetch | function | Ollama local provider |
| 2026-03-26 | *(Session 27 — fix)* | bracket strip order | TaxaTools | bug fix | `clean_taxon_names()`: brackets now stripped before capital-letter filter |
| 2026-03-26 | `verify_sci_names` | `verify_taxon_names` | TaxaTools | function | Renamed for consistency |
| 2026-03-26 | `create_taxon_name` | `create_taxon_names` | TaxaTools | function | Renamed (plural) |
| 2026-03-27 | `screen_spatial_formula` | `screen_spatial_formula` | TaxaHabitat → TaxaExpect | function | Moved; belongs with biodiversity modelling pipeline |
| 2026-03-27 | *(Session 30 — scope change)* | TaxaMatch revised to thin shell | TaxaMatch | package | Modeling functions moved to new TaxaLikely package |
| 2026-03-27 | *(Session 30 — new)* | TaxaLikely created | Ecosystem | package | Score→likelihood conversion; source: Universal_Biological_Classifier_Working_2.R |
| 2026-03-27 | *(Session 32 — breaking)* | `evaluate_likelihoods()` return type | TaxaLikely | interface | Now returns list `$likelihoods` + `$unresolved`; callers use `result$likelihoods` |
| 2026-03-27 | *(Session 32)* | `audit_reference_coverage()` `database` param removed | TaxaLikely | function | NCBI-only now via rentrez; taxize dependency removed |
| 2026-03-28 | *(Session 33 — new)* | `audit_barcode_coverage()` | TaxaLikely | function | Barcode-aware unreferenced species detection via NCBI nucleotide; replaces `audit_reference_coverage()` for eDNA. |
| 2026-03-28 | *(Session 33 — planned → Session 40)* | `expand_unreferenced_hypotheses()` | TaxaAssign | function | Moved to TaxaAssign (convergence point). |
| 2026-03-28 | *(Session 33 — fix)* | `assign_taxa_llm()` JSON parse regex | TaxaAssign | bug fix | Added `(?s)` PCRE flag; fixed range_status all-NA |
| 2026-03-29 | *(Session 34 — redesign)* | `audit_barcode_coverage()` | TaxaLikely | function | Corrected unreferenced definition; census redesigned: `in_reference`/`has_seqs_not_in_ref`/`unreferenced`/`is_complete`. `species_list` param added. |
| 2026-03-29 | *(Session 35)* | `suggest_unreferenced_species()` | TaxaAssign | function | Implemented in TaxaAssign. Returns `unreferenced_species_result` S3 object. |
| 2026-03-30 | *(Session 36)* | `expand_to_family` param | TaxaAssign | `suggest_unreferenced_species()` | Family-level unreferenced taxon expansion. |
| 2026-03-30 | *(Session 36)* | `habitat_fit` field | TaxaAssign | `assign_taxa_llm()` output | LLM returns `habitat_fit` ("expected"/"occasional"/"unlikely"). |
| 2026-03-30 | *(Session 36)* | `known_present`, `known_absent`, `absent_detection_prob` | TaxaAssign | `assign_taxa_llm()` params | Known presence/absence context. |
| 2026-03-31 | *(Session 39)* | `filter_redundant_hypotheses()` | TaxaMatch | function | Drop higher-rank rows superseded by finer-rank within same lineage + observation_id. |
| 2026-03-30 | *(Session 37)* | `ghost` (bool) | `hypothesis_type` (character) | TaxaAssign | Values: "specific_candidate" / "unreferenced_species" / "unreferenced_genus". |
| 2026-03-30 | *(Session 37)* | `habitat_affinity` | `habitat_fit` | TaxaAssign | LLM categorical column in `assign_taxa_llm()` output. |
| 2026-03-30 | *(Session 37)* | `missing_species` | `unreferenced_species` | TaxaAssign + TaxaLikely | `hypothesis_type` value. |
| 2026-03-30 | *(Session 37)* | `missing_genus` | `unreferenced_genus` | TaxaAssign + TaxaLikely | `hypothesis_type` value. |
| 2026-03-30 | *(Session 37)* | `Main_Habitat` | `main_habitat` | TaxaHabitat, TaxaExpect, TaxaFetch | snake_case consistency (145 occurrences). |
| 2026-03-30 | *(Session 38)* | `consensus_taxonomy()` | TaxaAssign | function | LCA among plausible posterior hypotheses. |
| 2026-03-30 | *(Session 38)* | `update_prior_from_consensus()` | TaxaAssign | function | Empirical Bayes refinement. |
| 2026-03-31 | *(Session 39)* | `suggest_plausible_ghosts()` | `suggest_unreferenced_species()` | TaxaAssign | function rename; S3 class `spg_result` → `unreferenced_species_result`. |
| 2026-03-31 | *(Session 39)* | `$ghosts` | `$unreferenced` | TaxaLikely | `audit_barcode_coverage()` return value; census column also renamed. |
| 2026-03-31 | *(Session 40)* | `expand_unreferenced_hypotheses()` | TaxaAssign | function | Moved from TaxaLikely; lives in `TaxaAssign/R/expand_unreferenced.R`. |
| 2026-04-06 | *(Session 49)* | `consensus_taxonomy()` | `posterior_consensus()` | TaxaAssign | **Breaking.** File: `R/consensus_taxonomy.R` → `R/posterior_consensus.R`. All callers updated. |
| 2026-04-06 | *(Session 49)* | `score_consensus()` | TaxaAssign | function | Conventional score-based consensus (min_score, max_gap, rank_thresholds, whitelist). |
| 2026-04-07 | *(Session 50)* | 5 workflow scripts replace monolithic workflow | TaxaLikely | workflow | `inst/TaxaLikely_workflow.R` superseded by `inst/workflows/1_*` through `5_*`. |
| 2026-04-09 | *(Session 52)* | `clean_taxon_names()` length-preserving | TaxaTools | function | **Breaking.** Invalid names now → NA instead of dropped. Callers needing old behavior: add `|> na.omit() |> unique()`. |
| 2026-04-13 | *(Session 56)* | `taxonomy_ranks` param | `rank_system` | TaxaTools | `create_taxon_names()` param — harmonize with TaxaLikely/TaxaAssign. |
| 2026-04-13 | *(Session 56)* | `rank_order` param | `rank_system` | TaxaMatch + TaxaAssign | `filter_redundant_hypotheses()` + `join_priors()` params. |
| 2026-04-13 | *(Session 56)* | `traitor_threshold` param | `mislabel_threshold` | TaxaLikely | `flag_reference_errors()` + `train_likelihood_model()`. |
| 2026-04-15 | *(Session 57)* | `%||%` exported from TaxaTools | TaxaTools | operator | 5 duplicate definitions removed from downstream packages. |
| 2026-04-15 | *(Session 57)* | `standard_ranks`, `extended_ranks`, `detect_ranks()` | TaxaTools | exported | Centralized rank definitions; downstream packages use `TaxaTools::standard_ranks`. |
| 2026-04-15 | *(Session 57)* | `combine_occurrence_sources()` | *(deleted)* | TaxaFetch | Dead code; superseded by `rename_cols()` + `stack_occurrences()`. |
| 2026-04-16 | *(Session 58)* | `build_priors()` | TaxaExpect | function | High-level wrapper: GBIF fetch → habitat → grid → model → priors → backbone translation. |
| 2026-04-16 | *(Session 58)* | `run_bayesian_pipeline()` | TaxaAssign | function | High-level wrapper for full Bayesian assignment. |
| 2026-04-16 | *(Session 58)* | `run_llm_pipeline()` | TaxaAssign | function | High-level wrapper for LLM-shortcut workflow. |
| 2026-04-28 | *(Session 60)* | TaxaFlag created | Ecosystem | package | Post-assignment anomalous detection flagging. |
| 2026-04-29 | *(Session 61)* | `remove_flagged_references()` | TaxaLikely | function | Remove mislabeled accessions; `model_params$reference_errors` slot added. |
| 2026-04-29 | *(Session 61)* | `rank_system` auto-detection | TaxaLikely | `train_likelihood_model()` + `evaluate_likelihoods()` | Default NULL auto-detects from column names. |
| 2026-05-01 | *(Session 64)* | `pdf_path` added to `pdf_structure` return | TaxaFetch | bug fix | Was missing; `call_api_pdf()` received NULL. |
| 2026-05-05 | *(Session 68)* | TaxaWizard created | Ecosystem | package | Conversational workflow designer. |
| 2026-05-06 | *(Session 69)* | Graph-based workflow engine | TaxaWizard | architecture | `inst/graph/workflow_graph.json` + 22 code snippets. |
| 2026-05-07 | *(Session 71)* | TaxaWorkflow | TaxaWizard | package | Renamed for clarity. |
| 2026-05-11 | *(Session 72)* | `verify_taxon_names()` NCBI direct bypass | TaxaTools | function | **Breaking for backbone_id=4.** Bypasses GlobalNames; uses batched `entrez_search()` + XML. |
| 2026-05-14 | *(Session 73)* | `min_phi` param | TaxaExpect | `generate_full_priors()` + `build_priors()` | Phi floor (default 2) prevents unstable MC posteriors. |
| 2026-05-19 | *(Session 77)* | `main_habitat` now required | TaxaAssign | `.latlon_to_grid()`, `join_priors()`, `run_bayesian_pipeline()` | **Breaking.** Habitat auto-selection removed. Must specify `main_habitat` in `site` param. |
| 2026-05-19 | *(Session 77)* | `census_genus_species()` | TaxaTools | function | GBIF backbone census: enumerate described species per genus/family. |
| 2026-05-20 | *(Session 79)* | `sample_id` | `observation_id` | TaxaMatch, TaxaLikely, TaxaAssign, TaxaFlag, TaxaWizard | **Breaking ecosystem rename** (~865 occurrences, ~141 files). L2 identifier renamed to eliminate ambiguity with L1 "sample" (collection event). `sample_id_col` → `observation_id_col` (TaxaMatch); `sample_col` → `event_col` (TaxaFlag); `sample_meta` → `event_meta` (TaxaAssign). |
| 2026-05-21 | *(Session 81)* | `habitat_observed_elsewhere` | `observed_in_habitat` | TaxaExpect | column + flag | TRUE = species recorded in this habitat type during training. |
| 2026-05-21 | *(Session 81)* | `least common ancestor` | `lowest common ancestor` | TaxaAssign + ecosystem | terminology | Standardized to conventional bioinformatics term (MEGAN, Kraken). |
| 2026-05-21 | *(Session 82)* | `options(TaxaID.llm_fn)` auto-detection | TaxaTools `.onAttach()` | global option | Priority: Anthropic > Gemini > OpenAI. All `llm_fn` defaults use `getOption("TaxaID.llm_fn", ...)`. |
| 2026-05-21 | *(Session 83)* | `R/model_registry.R` + `inst/model_tiers.json` | TaxaTools | module | Tier-based model discovery: `list_models()`, `refresh_models()`, `set_model()`. |
| 2026-05-21 | *(Session 83)* | `call_azure_api()` | TaxaTools | function | Azure OpenAI provider; `AZURE_OPENAI_API_KEY` env var. |
| 2026-05-22 | *(Session 84)* | `register_provider()` | TaxaTools | function | Session-only custom OpenAI-compatible provider registration. |
| 2026-05-23 | *(Session 85)* | `call_api()` | TaxaTools | function | **Generic LLM dispatcher.** All 5 provider functions now thin wrappers. `options(TaxaID.provider)` for active provider. `.onAttach()` sets `TaxaID.llm_fn = call_api`. |
| 2026-05-23 | *(Session 86)* | `LICENSE.md` + `DISCLAIMER.md` | *(centralised)* | All packages | Removed from package roots; centralised at `TaxaID/` root only. |
| 2026-05-26 | *(Session 87)* | Xeno-canto API v2 → v3 | TaxaLikely | `fetch_reference_recordings()` | **Breaking.** v3 requires API key (`XC_API_KEY` env var); endpoint changed. |
| 2026-05-26 | *(Session 87)* | `call_anthropic_api_pdf()` | `call_api_pdf()` | TaxaFetch | function rename + generalize | Now supports all vision-capable providers via `call_api(images=)`. |
| 2026-05-26 | *(Session 88)* | `build_reference_matrix()` | `build_sequence_matrix()` | TaxaLikely | **Breaking.** File: `R/build.R` → `R/build_sequence.R`. 36 files updated. |
| 2026-05-27 | *(Session 91)* | `read_reference_fasta()` `taxonomy` param | now NULL-default | TaxaLikely | **Breaking.** Must supply exactly one of `taxonomy` (data frame) or `taxonomy_file` (TSV path). |
| 2026-05-27 | *(Session 92)* | `show_tokens` + `max_input_tokens` params | `call_api()` | TaxaTools | Token logging + pre-flight guard. `attr(result, "tokens")` always attached. |
| 2026-05-28 | *(Session 95)* | TaxaWizard acoustic/image/local-reference | TaxaWizard | graph + metadata | 4 new input nodes, 2 new intermediate nodes, 8 new edges, 6 new snippets. |
| 2026-06-02 | *(Session 99)* | `score` → `score_original` in match object | TaxaMatch | column | `standardize_match_data()` output; `.evaluate_one_query()` updated; `assign_taxa_llm()` updated. |
| 2026-06-02 | *(Session 99)* | `likelihood_point_est` → `score_likelihood` | TaxaLikely, TaxaAssign | column | All functions, tests, workflows, docs updated. |
| 2026-06-02 | *(Session 99)* | `likelihood_mean` → `score_likelihood_mean` | TaxaLikely, TaxaAssign | column | All functions, tests, workflows, docs updated. |
| 2026-06-02 | *(Session 99)* | `likelihood_sd` → `score_likelihood_sd` | TaxaLikely, TaxaAssign | column | All functions, tests, workflows, docs updated. |
| 2026-06-02 | *(Session 99)* | `"unknown_species"` → `NA` / `"unreferenced_family"` | TaxaAssign | `taxon_name` / `hypothesis_type` | Catch-all row in `assign_taxa_llm()` output; `posterior_consensus.R` filter updated. |
| 2026-06-02 | *(Session 99)* | `unreferenced_candidates()`, `assign_scores()`, `model_likelihoods()`, `compute_likelihoods()` added | TaxaLikely | functions | Unified modular pipeline; `expand_consensus_candidates()` deprecated. |
| 2026-06-09 | *(Session 103)* | `detect_score_collapse()` | `detect_suppressed_candidates()` | TaxaLikely | function rename + rewrite | Full rewrite; old function removed. Returns named list (rule_detected, rules, perfect_only, max_score_ties, best_only, diagnostics). |
| 2026-06-06 | *(Session 101)* | `review_habitat` / `review_geography` / `review_scope` / `review_contaminant` | `habitat_plausibility` / `geographic_plausibility` / `scope_plausibility` / `contamination_risk` | TaxaFlag `review_assignments()` | column renames | Unified vocabulary: plausibility = likely/possible/unlikely; contamination_risk = low/moderate/high. |
| 2026-06-06 | *(Session 101)* | `flag_{type}` / `flag_{type}_score` / `flag_{type}_reason` | `{type}_risk` / `{type}_score` / `{type}_reason` | TaxaFlag `flag_contaminant()` | column renames | Direction also changed: old `"likely"` → new `"low"` risk. |
| 2026-06-08 | *(Session 104)* | `flag_prior_mismatch()` | `add_posthoc_assessment()` | TaxaFlag | function replacement | Redesign from risk/score/reason triplet to single categorical column (7 values: sensible, limited_evidence, unexpected, unprecedented, suspect, vague_rank, modeled). |
| 2026-06-23 | *(Session 117 — new param)* | `generate_undetected_diversity(taxonomy=)` | TaxaExpect | param added | Optional data frame (`taxon_name` + taxonomy columns). Joins taxonomy onto singleton-mirror rows for downstream `join_priors()` group descent. All 7 workflows updated. |
| 2026-06-23 | *(Session 117 — new column)* | `source_taxon_name` | TaxaExpect `generate_full_priors()` output | column added | Links each singleton-mirror row back to the observed species it was derived from. Preserved when `generate_full_priors()` appends `undetected` rows; used by `join_priors(singleton_taxonomy=)` to re-join taxonomy. |
| 2026-06-23 | *(Session 117 — new param)* | `join_priors(singleton_taxonomy=)` | TaxaAssign | param added | Optional data frame (`taxon_name` + taxonomy columns). Enables hierarchical mass-conserving group priors for unmodelled candidates via `.compute_dark_diversity_groups()` (phylum→class→order→family→genus). All 7 workflows updated. |
| 2026-06-23 | *(Session 117 — new columns)* | `dark_diversity_group`, `n_singletons_group`, `n_undetected_group` | TaxaAssign `join_priors()` output | columns added | Diagnostic columns added when `singleton_taxonomy` is supplied. `dark_diversity_group`: taxonomy label of the group a candidate was placed in (e.g. `"genus:Syngnathus"`, `"no_phylum"`, `"zero_orders_in_Malacostraca"`). `n_singletons_group`: singletons informing the group prior. `n_undetected_group`: unmodelled candidates in the group. |
| 2026-06-27 | *(Session 122)* | `is_valid_species_name()` | `is_plausible_binomial()` | TaxaTools | function rename | Better describes intent (plausibility heuristic, not formal validity). 13 files updated across TaxaTools, TaxaLikely, TaxaAssign. Test file renamed to test-is_plausible_binomial.R. |
| 2026-07-01 | *(Session 123)* | `add_slash_taxon()` gains `consensus_OTU`/`primary_taxon` | TaxaAssign | columns added | Non-breaking (fires only when `consensus_taxon` present). Replaces identical hand-rolled logic independently duplicated in 3 real workflows. |
| 2026-07-01 | *(Session 123)* | `audit_barcode_coverage()` "Common mistake" doc fix | TaxaLikely | doc only, no logic change | `match_df` must be the actual match object, not a length-curated training `reference_df` — confirmed via real Mugu data (*Mustelus mosis* case); 3 real workflows updated to pass the correct object. |
