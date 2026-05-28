# TaxaAssign Session Notes Archive
# Sessions 29–77. Current sessions live in TaxaAssign/CLAUDE.md.

**Session 29 (2026-03-27)**
- Full inventory completed; `compute_posterior()` is working and well-documented
- Interface contract confirmed from source: `observation_id`, `likelihood_point_est`,
  `likelihood_mean`, `likelihood_sd`, `prior_mean`, optional `prior_sd`
- Prior object mapping from TaxaExpect (`theta_mean` → `prior_mean`, `theta_sd` → `prior_sd`) documented
- TODO items: wire dev/ tests into testthat; migrate `%>%` to `|>`; implement planned functions

**Session 35 (2026-03-29)**
- `suggest_unreferenced_species()` implemented in `R/suggest_unreferenced_species.R`
  (originally named `suggest_plausible_ghosts()`; renamed in Session 39)
- Algorithm: LLM generates plausible species per genus → skip-list removal (species in match_df
  have references by definition) → NCBI barcode-count queries (retmax=0) on the plausible
  remainder only. Count=0 or NA → unreferenced; count>0 → has sequences but absent from reference.
- Return: `unreferenced_species_result` S3 class inheriting from `"character"` — behaves as a character vector
  (pass directly to `assign_taxa_llm(unreferenced_taxa=...)`); attributes `plausible` and `census`
  carry full details. `attr(result, "census")`: per-genus `plausible_count`, `ncbi_count`,
  `unreferenced_count`. `attr(result, "plausible")`: all LLM-generated species before NCBI filter.
- Barcode helpers (`.barcode_length_defaults`, `.resolve_barcode_lengths`, `.is_valid_species_name`)
  copied from TaxaLikely — TaxaLikely is NOT a dependency (its internals cannot be imported).
- `rentrez` added to Imports.
- `inst/TaxaAssign_llm_workflow.R` Section 4 updated: `suggest_unreferenced_species()` is now the
  primary approach; `audit_barcode_coverage()` retained as a commented slower alternative.
- 32 new tests passing; 0 errors, 0 warnings, 1 note (pre-existing CLAUDE.md note).

**Session 36 (2026-03-30)**
- `suggest_unreferenced_species()`: `expand_to_family = FALSE` parameter added. When TRUE, genera
  with no LLM-plausible species trigger a second LLM call for other genera in the same family.
  Family-level unreferenced taxa stored in `attr(result, "unreferenced_family")` (named vector: species → family)
  and `attr(result, "family_census")`. `.build_family_prompt()` and `.parse_family_response()`
  added as internal helpers.
- `suggest_unreferenced_species()` family prompt redesigned to return `{"species":…,"range_status":…}`
  objects. `.parse_family_response()` filters to plausible statuses (`native`,
  `introduced_established`, `documented_nearby`) BEFORE NCBI queries — eliminates implausible
  hypotheses at source. Fallback accepts plain string array with warning.
- `assign_taxa_llm()`: `habitat_fit` field added to LLM JSON response format (renamed from
  `habitat_affinity` in Session 37). Prompt rule 1 changed from "GEOGRAPHIC PROBABILITY ONLY"
  to integrate habitat suitability. Prior weight scale now has two dimensions:
  range_status × habitat_fit. `habitat_fit` ("expected"/"occasional"/"unlikely") passes through
  to output data frame.
- `assign_taxa_llm()`: `known_present`, `known_absent`, `absent_detection_prob` parameters
  added. `known_present`: character vector → LLM context only (co-occurrence + habitat
  reasoning). `known_absent`: character vector or data frame with `taxon_name` +
  `detection_prob` → LLM context AND mathematical suppression: `prior × (1 - p_det)`,
  renormalized. Applied after NA-fill, before rescale. A "Survey context" block is injected
  into the prompt when either is supplied.
- `.score_to_likelihood()`: family-level unreferenced taxon insertion via `unreferenced_family_map` parameter.
  Species whose genus is absent from candidates but whose family IS represented are inserted with
  likelihood = median exp-score of all candidates in that family.
- Workflow script (`inst/TaxaAssign_llm_workflow.R`) now includes placeholder functions
  `f_filter_redundant_higher_hypotheses()` and `f_score_ordinal_col()` for match_df
  pre-processing. These are to be implemented properly in TaxaMatch and TaxaTools
  respectively — see their CLAUDE.md files for specifications.
- Normalization discussion: confirmed that likelihood normalization constant cancels in
  posterior step; excluding implausible unreferenced species (prior ≈ 0) does not bias posteriors.
  `unknown_species` catch-all absorbs unmodelled diversity. Independence assumption
  (L ⊥ P) is technically violated due to reference database geographic bias and LLM
  conflation of rarity with absence, but practical impact is minor for well-sampled regions.
- All tests passing: 0 errors, 0 warnings, 1 note (pre-existing CLAUDE.md note).

**Session 38 (2026-03-30)**
- `consensus_taxonomy()` implemented in `R/consensus_taxonomy.R`:
  - LCA walks `rev(rank_system)` finest-to-coarsest; first rank where all plausible hypotheses agree
  - All named hypotheses included (`specific_candidate`, `unreferenced_species`, `unreferenced_genus`);
    only `unknown_species` catch-all excluded. Family-level unreferenced taxa now correctly contribute to LCA.
  - `rank_system` auto-detected from standard taxonomy columns in `posterior_df`
  - `backbone_id` param added (default 11 = GBIF) and passed through to `verify_taxon_names()`
  - `.extract_rank_values()` bug fixed: when explicit genus column has NA (unreferenced rows), falls back
    to deriving genus from binomial (`sub(" .*", "", taxon_name)`)
  - `lookup_missing_taxonomy = TRUE` path fixed: was matching on non-existent `verified$taxon_name`
    (should be `user_supplied_name`) and trying flat columns that don't exist in `verify_taxon_names()`
    output. Now uses `change_backbone()` to parse `classification_path`/`classification_ranks` into
    flat columns, then matches on `user_supplied_name`
  - Propagates `prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1`, `taxon_changed` when
    present in input (set by `update_prior_from_consensus()`)
  - 53 tests passing
- `update_prior_from_consensus()` implemented in `R/update_prior_from_consensus.R`:
  - One-pass empirical Bayes: confirmed species (from `is_resolved = TRUE` rows) get prior boost
    in unresolved samples only; `compute_posterior()` re-run on unresolved rows only
  - `prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1` joined into returned dataframe
    so `consensus_taxonomy()` can propagate them automatically
- `inst/TaxaAssign_consensus_workflow.R` created: standalone workflow starting from `result`
  covering overview, resolved/ambiguous/unresolvable inspection, threshold sensitivity, and
  winner-takes-all vs LCA comparison
- `inst/TaxaAssign_llm_workflow.R`: Section 11 added with `consensus_taxonomy()` usage;
  Sections 6–7 fixed to use `hypothesis_type` instead of old `ghost` column
- 0 errors, 0 warnings throughout

**Session 37 (2026-03-30)**
- Ecosystem-wide terminology standardisation:
  - `ghost` (bool) → `hypothesis_type` (character) in TaxaAssign output; values aligned with TaxaLikely
  - `habitat_affinity` → `habitat_fit` (LLM categorical: "expected"/"occasional"/"unlikely")
    Note: `habitat_affinity` is retained in TaxaHabitat for species' numeric habitat weights — different concept
  - `missing_species` → `unreferenced_species`; `missing_genus` → `unreferenced_genus` (TaxaAssign + TaxaLikely)
  - `Main_Habitat` → `main_habitat` (TaxaHabitat, TaxaExpect, TaxaFetch — 145 occurrences)
  - `ctx$habitat` → `ctx$main_habitat` in `assign_taxa_llm()` context object
  - LLM prompt rule 1 generalised: "Assign a weight proportional to the probability that a
    random sample from this site belongs to this species" (removes DNA-specific framing)
  - `magrittr` removed from `compute_posterior.R` and DESCRIPTION; `%>%` → `|>` throughout
  - Duplicate `cli_inform("Computing posteriors...")` removed from `assign_taxa_llm()`
- `consensus_taxonomy()` planned: one row per observation_id, LCA among plausible hypotheses,
  parameters `cumulative_threshold = 0.9` + `min_posterior = 0.05`; list columns for
  `plausible_taxa` and `plausible_posteriors`. Taxonomy columns to be retained through
  `.score_to_likelihood()` for full-pipeline LCA support.
- All checks passing: TaxaAssign 0 errors/0 warnings, TaxaLikely 0 errors/0 warnings,
  TaxaHabitat 0 errors/0 warnings/0 notes, TaxaExpect 0 errors/0 warnings/0 notes.

**Session 46 (2026-04-03)**
- `build_context()` implemented in `R/build_context.R`:
  - Auto-populates `ctx` data frame (ecoregion, main_habitat, date) from candidate taxon names
  - Pipeline: `TaxaHabitat::build_habitat_prompt(geographic_context=...)` → `llm_fn()` per chunk →
    `parse_hierarchical_habitat_response()` → `consensus_habitat()` → LLM synthesis call
  - Synthesis call: asks LLM to describe the likely sampling habitat from proportions + species
    in 3-8 words. Solves the argmax problem for transitional environments (e.g. coastal lagoon
    returns "Freshwater" via argmax but "coastal lagoon / estuary" via synthesis)
  - Falls back to mechanical consensus if synthesis parsing fails
  - Returns one-row data frame with `attr(ctx, "habitats_df")` and `attr(ctx, "habitat_proportions")`
  - Internal helpers: `.build_synthesis_prompt()`, `.parse_synthesis_response()`
  - TaxaHabitat added to Suggests (not Imports — avoids sf/terra transitive dependency)
- TaxaHabitat changes (Session 46):
  - `build_habitat_prompt()`: `geographic_context` param adds `GEOGRAPHIC CONTEXT:` block and
    `ecoregion_best_guess` column to LLM prompt
  - `parse_hierarchical_habitat_response()`: `ecoregion_best_guess` protected from numeric detection
  - `consensus_habitat()`: new exported function in `assign_habitat_biological.R`; assemblage-level
    consensus from per-species weights; modal ecoregion extraction
  - `.detect_habitat_cols()`: shared internal extracted from `assign_habitat_biological()`
- LLM workflow (`inst/TaxaAssign_llm_workflow.R`): Section 2 reordered — LLM provider choice
  moved before context; `build_context()` shown as Option A (default), manual `ctx` as Option B
- 25 TaxaHabitat tests passing (18 new), 249 TaxaAssign tests passing (12 new)
- `devtools::check()` clean on both packages

**Session 49 (2026-04-06)**
- `consensus_taxonomy()` renamed to `posterior_consensus()` across all R source, tests, workflow scripts
  - File renamed: `R/consensus_taxonomy.R` → `R/posterior_consensus.R`
  - Test file renamed: `test-consensus_taxonomy.R` → `test-posterior_consensus.R`
  - All roxygen references updated; man pages regenerated
- `score_consensus()` implemented in `R/score_consensus.R`:
  - Conventional score-based consensus (no model, no priors, no LLM)
  - Algorithm: min_score filter → max_gap from top hit → LCA → rank_thresholds cap → whitelist upranking
  - Conventional eDNA thresholds from GITA pipeline: `c(species = 98, genus = 95, family = 90, order = 85)`
  - Reuses `.find_lca()` and `.extract_rank_values()` internals from posterior_consensus.R
  - Internal helpers: `.score_consensus_one()`, `.cap_rank_by_threshold()`, `.uprank_to_whitelist()`
  - Output: `consensus_taxon`, `consensus_rank`, `is_resolved`, `top_score`, `n_retained`, `n_taxa`, `retained_taxa`, plus optional `rank_capped` and `whitelist_capped`
  - 22 tests in `test-score_consensus.R` covering all branches
- Both workflow scripts updated:
  - `TaxaAssign_llm_workflow.R`: Sections 6–8 added (score_consensus, comparison, report)
  - `TaxaAssign_bayesian_workflow.R`: Sections 6–7 added (score_consensus, comparison)
  - Comparison outputs: taxon/rank agreement rates, resolution cross-tabulation, disagreement list, posterior-finer vs score-finer counts
- `generate_report()`: now supports both consensus types (score-based and posterior-based)
  - `result` parameter accepts NULL (for score-based consensus where no posteriors exist)
  - Consensus type auto-detected from column presence (`top_score` → score, `consensus_posterior` → posterior)
  - Methods text adapts to consensus type: score-based describes min_score, max_gap, rank_thresholds, whitelist, LCA
  - Results (LLM): prompt instructions adapt to consensus type
  - Results (template): score-based paragraph reports median/mean top scores, rank capping, whitelist upranking
  - Old comparison-based approach (`score_consensus` param, `.extract_comparison_stats()`) removed
  - LLM workflow shows Option A (posterior) and Option B (score) `generate_report()` calls
  - Fixed split-string `sprintf` bug in rank_thresholds sentence (format string split across args)
- `devtools::check()` clean: 0 errors, 0 warnings, 1 note (pre-existing CLAUDE.md)

**Session 47 (2026-04-04)**
- Beta-distributed priors replace Normal-distributed priors throughout:
  - `compute_posterior()`: accepts `prior_alpha`/`prior_beta` columns; samples via `rbeta()`.
    When absent, priors treated as fixed (no prior uncertainty). `prior_sd` column removed entirely.
    Likelihoods still sampled from Normal (unchanged). 12 tests covering Beta path.
  - `assign_taxa_llm()`: LLM prompt now requests `information_quality` ("high"/"moderate"/"low")
    per taxon — measures how much published data exists about the taxon in the focal region.
    New `prior_phi` parameter: named vector mapping quality → phi (effective sample size of LLM judgment).
    Default `c(high = 50, moderate = 10, low = 3)`. After prior rescaling:
    `prior_alpha = prior_mean * phi`, `prior_beta = (1 - prior_mean) * phi`.
    Accepts scalar (uniform phi) or NULL (disable Beta priors). Default `n_sims` changed 0 → 1000.
  - `join_priors()`: passes TaxaExpect `alpha`/`beta` directly as `prior_alpha`/`prior_beta`
    (no longer derives `prior_sd` from them). Dark diversity fallback coalesces alpha/beta.
  - **Statistical rationale:** TaxaExpect produces Beta(alpha, beta) priors; the old Normal
    approximation N(mean, sd) was biased for small priors (floor-at-zero creates point mass)
    and unbounded above 1. Beta sampling is correct by construction. The LLM workflow now
    uses the same Beta framework via phi mapping, achieving parallelism between workflows.
  - Debugged against real MiFish eDNA data (3 samples): LLM reliably returns `information_quality`;
    high-info taxa (phi=50) produce posterior_sd ~0.025; moderate-info taxa (phi=10) produce ~0.087.
- 0 errors, 0 warnings, 1 note (pre-existing CLAUDE.md) on `devtools::check()`

**Session 44 (2026-04-02)**
- `consensus_taxonomy()`: `species_reference` parameter added for downranking unresolved coarse-rank consensus
  - Accepts `unreferenced_species_result` (extracts `attr(x, "plausible")`, derives genus from binomial) or a data.frame (e.g. `taxaexpect_species_df`)
  - After LCA, `.downrank_consensus()` walks each unresolved row down rank_system: if exactly one finer taxon in reference → downrank (recursive). Stops at >1 option (conservative).
  - New output column `downranked` (logical, always present when species_reference non-NULL)
  - New internal helpers: `.build_species_ref()`, `.downrank_consensus()`
  - LLM workflow: pass `unreferenced_species` (same object as `assign_taxa_llm(unreferenced_taxa=...)`; `plausible` attr contains referenced species the LLM flagged, e.g. Leptocottus armatus)
  - Bayesian workflow: pass `taxaexpect_species_df`
  - Both workflow scripts updated
- `devtools::check()` clean: 0 errors, 0 warnings, 1 note (pre-existing CLAUDE.md)
- Diagnostic: LLM vs Bayesian workflow comparison begun (deferred to Session 45). Key finding: Clinocottus appears in LLM posteriors but not Bayesian — LLM adds it via `suggest_unreferenced_species()` plausible list; TaxaExpect does not predict it at this grid cell. Bayesian more parsimonious; suspected cause is LLM prior diffuseness vs site-specific TaxaExpect priors.

**Session 43 (2026-04-02)**
- Audited all TaxaAssign functions — all 6 exported functions confirmed fully implemented, no stubs
- Bug fix: `TaxaAssign_bayesian_workflow.R` Section 8 passed `threshold = 0.95` to `consensus_taxonomy()`; correct param is `cumulative_threshold`. Would have errored at runtime.
- `TaxaAssign_bayesian_workflow.R` Section 5 rewritten: 3-step `sample_meta` construction guide (check/add location column → map locations to `grid_id` + `main_habitat` → join; unmapped-sample warning). Sections renumbered 1–8.
- `inst/PRIOR_LIKELIHOOD_MATCHING.md`: `### Ghost Prior Values` → `### Dark Diversity Prior Values` (last remaining ghost-terminology remnant, flagged in Session 40)
- `tests/testthat/test-compute_posterior.R`: placeholder replaced with 8 real tests (23 assertions), all passing. Covers: structure/sums-to-1, all-SD-zero skips simulation, n_sims=0, missing prior_sd, missing required columns, NA in likelihood_sd, single-hypothesis sample, output sort order.
- All planned functions removed from Function Inventory (superseded by inline workflow logic or existing function internals): `join_likelihood_prior()`, `normalize_likelihood()`, `validate_likelihood()`, `validate_prior()`, `summarize_posterior()`, `plot_posterior()`
- TaxaExpect installed; `devtools::check()` confirmed clean (0 errors, 0 warnings, 0 notes)
- Corrupted `TaxaLikely/inst/real_likelihoods.rds` deleted (stale artifact; Stage B regenerates to installed package dir)
- 0 errors, 0 warnings throughout

**Session 40 (2026-03-31)**
- `expand_unreferenced_hypotheses()` implemented in `R/expand_unreferenced.R` (moved here from TaxaLikely — belongs in TaxaAssign because it is the convergence point for TaxaLikely likelihoods + TaxaExpect priors, mirroring `assign_taxa_llm()` in the LLM workflow)
- Expansion logic:
  - H2 (`"unreferenced_species"`) row: genus label in `taxon_name`; species in `unreferenced_df` matching that genus get H2 likelihood values; generic row retained when no genus match
  - H3 (`"unreferenced_genus"`) row: family label in `taxon_name`; species in `unreferenced_df` matching that family AND a different genus from H2 get H3 likelihood values; generic row retained when no family match
  - H1 (`"specific_candidate"`) rows: passed through unchanged
  - Works across multiple `observation_id` values; case-insensitive genus/family matching
- 10 tests in `tests/testthat/test-expand_unreferenced.R` covering all branches; check passes 0 errors / 0 warnings
- `inst/TaxaAssign_bayesian_workflow.R` created: 7-section end-to-end workflow for the non-LLM (Bayesian) pipeline covering: likelihoods (TaxaLikely), priors (TaxaExpect), unreferenced expansion, coverage constraints, likelihood–prior join + dark diversity fallback, `compute_posterior()`, `consensus_taxonomy()`
- TaxaLikely Stage D (expand_unreferenced) stripped from `inst/TaxaLIkely_workflow.R`; pointer added to `TaxaAssign_bayesian_workflow.R`
- Settings permissions simplified: broad wildcard rules `Bash(Rscript:*)`, `Bash(R -e:*)`, `Bash(afplay:*)` replace the previous long list of specific devtools command patterns

**Session 39 (2026-03-31)**
- "Ghost species" terminology replaced throughout with precise terms:
  - `suggest_plausible_ghosts()` → `suggest_unreferenced_species()` (file + function)
  - S3 class `"spg_result"` → `"unreferenced_species_result"`
  - param `ghost_taxa` → `unreferenced_taxa` in `assign_taxa_llm()`
  - attribute `ghost_family` → `unreferenced_family` on `unreferenced_species_result` objects
  - census column `ghost_count` → `unreferenced_count`
  - `audit_barcode_coverage()$ghosts` → `$unreferenced` (TaxaLikely)
  - All comments, roxygen docs, workflow scripts, and CLAUDE.md files updated ecosystem-wide
  - TaxaFetch test: `"Ghost sp."` → `"Unknown sp."`

**Session 61 (2026-04-29)**
- Bug fixes:
  - `expand_unreferenced_hypotheses()`: empty `unreferenced_df` now drops all H2/H3 rows
    (previously returned them unchanged, causing downstream NA posteriors)
  - `join_priors()`: new `taxonomy_lookup` param fills taxonomy columns from match_df
    reference taxonomy; derives genus from species binomials when genus column is NA.
    Fixes all-NA taxonomy in posteriors for unreferenced species.
- Pipeline optimizations applied to `run_bayesian_pipeline()`:
  - A: Audit only genera present in H2/H3 likelihood rows (fewer NCBI queries)
  - B: Pre-filter unreferenced_df to relevant genera/families
  - C: Pre-filter taxaexpect_priors to site + Tier 3 rows for dark diversity
  - ~16% speedup with 100% output agreement vs unoptimized workflow
- `run_bayesian_pipeline()` enhancements:
  - `model_rank_system` param (auto-detected): separates model ranks from taxonomy ranks
  - `rank_system` default changed to `c("order", "family", "genus", "species")`
  - Stage 0: auto-reads `model_params$reference_errors` and removes flagged accessions
  - `site` param: `main_habitat` now optional; auto-selects from priors when omitted or
    when specified habitat not available at resolved grid_id
- `run_llm_pipeline()`: new `reference_errors` param for error filtering (accepts
  `model_params$reference_errors`)
- `.latlon_to_grid()`: `main_habitat` defaults to NULL; auto-selects habitat with most
  prior rows at resolved grid. Messages user with selection and alternatives.
- `.resolve_site()`: no longer stops when `site = list(lat, lon)` lacks `main_habitat`
- `inst/Wrapper_full_workflow.R`: removed `main_habitat` from site list to exercise
  auto-resolution; now runs end-to-end with correct habitat matching
- `inst/TaxaAssign_bayesian_workflow_new.R`: created as optimized variant with timing
  infrastructure and baseline comparison
- 378 tests passing; `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 62 (2026-04-30)**
- `.latlon_to_grid()`: auto-select message now includes per-habitat row counts
  (e.g., `"prior rows: Marine (847), Freshwater (356)"`) for better user context
- `run_bayesian_pipeline()`: new species-habitat consistency check after site resolution.
  Warns if <50% of candidate taxa have non-zero priors at the resolved habitat; suggests
  `habitat_scheme = 'IUCN_L1'` or coordinate review. Uses `theta_mean` (from TaxaExpect
  priors) not `prior_mean` (which doesn't exist until after `join_priors()`)
- `devtools::check()`: 0 errors, 0 warnings, 1 note (benign timestamp)

**Session 67 (2026-05-04)**
- `llm_fn` default changed from `TaxaTools::call_anthropic_api` to `NULL` in all 4 exported
  functions: `assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`,
  `suggest_unreferenced_species()`. Eliminates hard install-time dependency on TaxaTools.
- `.resolve_llm_fn()` internal helper added to `R/site_utils.R`: resolves NULL → TaxaTools
  default at runtime with clear error if TaxaTools not installed.
- `generate_report()`: default changed to `llm_fn = NULL` (already handled NULL gracefully
  with template fallback, so no resolver call needed).
- `test-run_pipelines.R` created: 10 input validation tests for `run_bayesian_pipeline()`,
  `run_llm_pipeline()`, and `.resolve_llm_fn()`. All offline (validation errors fire before
  any computation). Key patterns: `auto_context = FALSE` + `detect_unreferenced = FALSE`
  to prevent LLM calls; `match.arg()` error matching.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 73 (2026-05-14)**
- `join_priors()`: dark diversity floor for habitat-mismatched modelled species. Species the model
  has seen (non-NA alpha) but with theta ≈ epsilon due to habitat mismatch now get promoted to the
  dark diversity fallback (mean of Tier 3 alpha/beta). Prevents never-observed species from having
  higher priors than modelled species at the wrong habitat. Message: "promoted N modelled row(s)
  with habitat-mismatch priors to dark diversity floor."
- `join_priors()`: `site` param default changed from required to `NULL`; auto-resolves from
  `attr(priors, "search_center")` when available (set by `build_priors()`).
- `join_priors()`: lat/lon string shortcut — bare `grid_id` string auto-selects best habitat.
- `join_priors()`: improved missing `grid_id` warning messages with habitat row counts.
- Diagnostic findings (not code changes):
  - G. simplicidens vs G. nigricans: with equal (dark floor) priors, likelihoods correctly
    determine outcome — system working as designed.
  - Clevelandia ios ESV_067349: 97.6% score below model expectation (logit 8.21 ≈ 99.97%),
    H1 likelihood dropped by `ratio_threshold`. `species_reference` param in
    `posterior_consensus()` would recover via monotypic-genus downranking.
- `devtools::check()`: 0 errors, 0 warnings (vignettes skipped — pandoc not available)

**Session 77 (2026-05-19)**
- `run_bayesian_pipeline()`: new Stage 1b — three-tier H2 phantom suppression using GBIF
  genus census from `attr(taxaexpect_priors, "gbif_genus_census")`.
  - Reads census attached by `build_priors()` (no additional API calls).
  - Computes `setdiff(described_species, match_df$species)` locally per genus.
  - **Complete genera** (n_missing == 0): H2 "unreferenced_species" rows removed from
    `top_likelihoods`. Prevents biologically impossible phantoms from stealing posterior mass.
  - **Singleton-missing genera** (n_missing == 1): H2 rows renamed to the specific missing
    species binomial; `taxon_name_rank` set to "species".
  - **Incomplete genera** (n_missing > 1): no change (current behavior preserved).
  - GBIF `all_species` list fed to `audit_barcode_coverage(species_list = ...)`, replacing
    NCBI taxonomy subtree queries (more complete and reliable).
- **Breaking:** `main_habitat` now required in `site` parameter (was auto-selected).
  - `.latlon_to_grid()`: errors when `main_habitat` is NULL, listing available habitats
    at the resolved grid cell with row counts and example syntax.
  - `join_priors()`: bare grid_id string shortcut now errors instead of auto-selecting.
  - `join_priors()`: NULL + `search_center` fallback also errors requesting habitat.
  - `.resolve_site()`: multi-site data frame with lat/lon now requires `main_habitat` column.
  - Roxygen docs for `site` param updated in `join_priors()` and `run_bayesian_pipeline()`.
  - TaxaWizard `lik_prior_to_post.R` snippet simplified (removed inline auto-select logic).
  - TaxaWizard `phase_parameterize.md` updated: habitat is required, not optional.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.
