# CLAUDE.md — TaxaAssign
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-06-24 (Session 118 — adjust_inat_range_priors() added; check_inat_range() added to TaxaFetch)

---

## Package Purpose
Implements Bayesian taxonomic assignment by combining likelihood and prior objects to
compute posterior probabilities. Final step in the TaxaID pipeline. Designed to accept
any conforming likelihood and prior objects — inputs may come from TaxaMatch/TaxaExpect
or be user-supplied from outside the ecosystem.

**Status: Thirteen working functions (10 core + 3 wrappers/utilities). All planned functions removed — superseded by inline workflow logic or existing function internals.**

---

## The Bayes Step

1. Normalize likelihoods *within* `observation_id` across all competing hypotheses (sum to 1)
2. Multiply normalized likelihood × prior
3. Normalize product to produce posterior (sum to 1 per `observation_id`)
4. Optional Monte Carlo path: sample likelihoods from Normal(mean, sd), priors from Beta(alpha, beta); propagate both sources of uncertainty into posterior

---

## Function Inventory

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `adjust_inat_range_priors()` | Elevate `prior_alpha`/`prior_beta`/`prior_mean` to Tier 2 singleton-mirror floor for unmodelled taxa confirmed `in_range = TRUE` by iNaturalist geomodel with sufficient observation coverage. Adds `inat_range_elevated` column. Guard: no elevation when singleton floor ≤ current prior. | Complete | R/adjust_inat_range_priors.R |
| `compute_posterior()` | Core Bayes update: likelihood × prior → posterior | Complete | R/compute_posterior.R |
| `expand_unreferenced_hypotheses()` | Replace generic H2/H3 rows from TaxaLikely with named unreferenced species; bridges TaxaLikely likelihoods to TaxaExpect priors | Complete | R/expand_unreferenced.R |
| `suggest_unreferenced_species()` | LLM-first unreferenced species detection: plausible species per genus → reference-check → unreferenced vector; optional family expansion. data_type param ("eDNA"/"acoustic"/"image") routes to NCBI queries (eDNA) or set-membership check vs reference_species (acoustic/image). | Complete | R/suggest_unreferenced_species.R |
| `assign_taxa_llm()` | LLM-shortcut pipeline: score-based likelihoods + LLM priors → posteriors | Complete | R/assign_taxa_llm.R |
| `posterior_consensus()` | LCA-based consensus from posterior dataframe; one row per `observation_id` | Complete | R/posterior_consensus.R |
| `score_consensus()` | Conventional score-based consensus (min_score, max_gap, rank_thresholds, whitelist); one row per `observation_id` | Complete | R/score_consensus.R |
| `update_prior_from_consensus()` | Boost priors for confirmed species in unresolved samples; re-run `compute_posterior()` | Complete | R/update_prior_from_consensus.R |
| `build_context()` | Auto-populate `ctx` (ecoregion, main_habitat, date) from taxon names via TaxaHabitat + LLM synthesis | Complete | R/build_context.R |
| `generate_report()` | Publication-ready Methods + Results text; hybrid template (Methods) + LLM (Results) with template fallback | Complete | R/generate_report.R |
| `join_priors()` | Bridge likelihoods to priors: join TaxaExpect priors with dark diversity fallback, fill taxonomy, filter redundant hypotheses. `site` requires `main_habitat` — accepts `list(lat, lon, main_habitat)` or `list(grid_id, main_habitat)` or multi-site data frame. Modelled species with habitat-mismatch priors promoted to dark diversity floor. **Session 108:** unmodelled species (never detected) now fall back to the `global_floor` row (Beta(1, N_total-1)) rather than the site-level dark mean. **Session 109:** `expansion_taxonomy`, `expansion_min_prior` (default 0.05), `expansion_cumulative_prior` (default 0.90) params added. When a likelihood row has `taxon_name_rank` coarser than species (e.g. family-rank identification), and `expansion_taxonomy` is supplied (a `fill_higher_ranks()` result mapping priors species to genus/family), the coarse-rank row is replaced by species-level hypothesis rows filtered by the same cumulative-threshold logic as `posterior_consensus()`. Rows without matching species in priors fall back to dark floor. `hypothesis_type = "rank_expanded"` marks expanded rows. When `expansion_taxonomy` is NULL and coarse-rank rows are present, a warning with instructions is emitted. **Session 117:** `singleton_taxonomy` param added (optional data frame with `taxon_name` + taxonomy columns, e.g. `occurrences_std`). When supplied, unmodelled (unreferenced) candidates receive hierarchical mass-conserving group priors via `.compute_dark_diversity_groups()` (phylum→class→order→family→genus recursive descent) rather than a flat global floor. Candidates with unknown phylum (`no_phylum` group) fall back to the global floor individually. Adds three diagnostic columns to output: `dark_diversity_group` (character — taxonomy label of group), `n_singletons_group` (integer — singletons in the group), `n_undetected_group` (integer — unmodelled candidates in the group). Requires TaxaExpect >= Session 117 (`source_taxon_name` in `generate_full_priors()` output and `taxonomy` param in `generate_undetected_diversity()`). | Complete | R/join_priors.R |
| `run_bayesian_pipeline()` | High-level wrapper: TaxaLikely likelihoods + TaxaExpect priors → full Bayesian workflow (~10 calls → 1). Auto-filters errors from model_params, auto-resolves site habitat. Stage 1b: three-tier H2 phantom suppression via GBIF genus census (suppress complete, rename singleton-missing, keep incomplete). GBIF species list fed to `audit_barcode_coverage(species_list=)`. | Complete | R/run_bayesian_pipeline.R |
| `run_llm_pipeline()` | High-level wrapper: LLM-shortcut workflow (~7 calls → 1); optional auto-context + unreferenced detection + report. Optional `reference_errors` param. | Complete | R/run_llm_pipeline.R |
| `report_assign()` | Generate `report_section` summarizing taxonomic assignment (workflow type, resolution rate, posterior/score stats). For `assemble_report()`. | Complete | R/report_assign.R |

**Internal helpers (not exported):**

| Function | Purpose | Source file |
|---|---|---|
| `.resolve_llm_fn()` | NULL-default resolver: returns user-supplied `llm_fn`, then checks `getOption("TaxaID.llm_fn")` (set by TaxaTools `.onAttach()`), then falls back to `TaxaTools::call_anthropic_api`; clear error if TaxaTools not installed | R/site_utils.R |
| `.resolve_site()` | Site resolution: lat/lon → nearest grid_id from priors; multi-site support | R/site_utils.R |
| `.latlon_to_grid()` | Haversine nearest-grid lookup with habitat auto-selection | R/site_utils.R |
| `.run_consensus_and_report()` | Shared consensus → empirical Bayes → report helper for both pipeline wrappers | R/run_bayesian_pipeline.R |

---

## Function Signature

### `compute_posterior(likelihood_w_prior, n_sims = 1000)`

**Input:** dataframe, one row per hypothesis per sample. Required columns:

| Column | Type | Description |
|---|---|---|
| `observation_id` | any | Groups competing hypotheses; one unique value per observation |
| `score_likelihood` | numeric | Point estimate of likelihood for this hypothesis |
| `score_likelihood_mean` | numeric | Mean of likelihood distribution |
| `score_likelihood_sd` | numeric | SD of likelihood distribution (NA → replaced with 0 + warning) |
| `prior_mean` | numeric | Prior probability for this hypothesis |
| `prior_alpha` | numeric | Beta shape1 parameter (optional; enables Beta-distributed prior sampling) |
| `prior_beta` | numeric | Beta shape2 parameter (optional; must accompany `prior_alpha`) |

When `prior_alpha`/`prior_beta` are present, MC samples priors from `Beta(alpha, beta)` — correctly bounded [0,1]. When absent, priors are treated as fixed (no prior uncertainty in MC). `prior_sd` is no longer used (removed 2026-04-04).

Any additional columns (e.g. `taxon_name`, `rank`, `hypothesis_type`) are passed through unchanged.

**Output:** same dataframe + 4 columns, sorted by `observation_id` asc then `posterior_mean` desc:

| Column | Description |
|---|---|
| `posterior_point_est` | Deterministic posterior from point estimates |
| `posterior_mean` | Mean posterior across Monte Carlo simulations (= `posterior_point_est` if no sims) |
| `posterior_sd` | SD of posterior across simulations (= 0 if no sims) |
| `confidence_score` | Fraction of simulations in which this hypothesis had the highest posterior |

**Two computation paths:**
- **Point estimate path** — always runs; uses `score_likelihood` and `prior_mean`
- **Monte Carlo path** — runs only when `n_sims > 0` AND at least one source of uncertainty exists (non-zero `score_likelihood_sd`, or `prior_alpha`/`prior_beta` present). Likelihoods sampled from `Normal(mean, sd)` floored at 0; priors sampled from `Beta(alpha, beta)`.

**Internal helper:** `normalize_vec(x)` — normalizes vector to sum to 1; returns uniform distribution if all zeros (prevents division by zero).

---

## Function Signature: `assign_taxa_llm()`

```r
assign_taxa_llm(match_df,
                context               = NULL,
                context_group         = NULL,
                rank_system           = NULL,
                llm_fn                = TaxaTools::call_anthropic_api,
                score_threshold       = 80,
                top_n                 = 10L,
                score_sharpness       = 0.1,
                unknown_lik_weight    = 0.05,
                unreferenced_taxa     = NULL,
                known_present         = NULL,
                known_absent          = NULL,
                absent_detection_prob = 0.80,
                taxa_per_call         = 30L,
                pause_seconds         = 1,
                prior_phi             = c(high = 50, moderate = 10, low = 3),
                prior_weight_guide    = list(...),  # 7 range-status x habitat-fit ranges
                n_sims                = 1000L,
                verbose               = FALSE)
```

**Output columns** (all input columns preserved + posterior columns):
`observation_id`, `taxon_name`, `taxon_name_rank`, `hypothesis_type`, `range_status`,
`habitat_fit`, `information_quality`, `score_likelihood`, `score_likelihood_mean`, `score_likelihood_sd`,
`prior_mean`, `prior_alpha`, `prior_beta`, `posterior_point_est`, `posterior_mean`, `posterior_sd`,
`confidence_score`. Taxonomy columns from `match_df` (e.g. `family`, `genus`, `species`)
are carried through via `rank_system` detection and used by `consensus_taxonomy()`.
`hypothesis_type` values: `"specific_candidate"`, `"unreferenced_species"` (congener without barcode reference),
`"unreferenced_genus"` (family-level unreferenced taxon), `"unreferenced_family"` (catch-all; `taxon_name = NA`).
`prior_alpha`/`prior_beta` present when `prior_phi` is non-NULL.

**Key parameters:**

| Parameter | Purpose |
|---|---|
| `unreferenced_taxa` | `unreferenced_species_result` from `suggest_unreferenced_species()`; unreferenced congeners inserted per sample; `unreferenced_family` attribute activates family-level unreferenced taxon insertion |
| `known_present` | Character vector; passed to LLM as ecological context to sharpen co-occurrence and habitat reasoning — no math step |
| `known_absent` | Character vector or data frame (`taxon_name` + `detection_prob`); passed to LLM as context AND applies mathematical suppression: `prior × (1 - p_det)`, then renormalize |
| `absent_detection_prob` | Default detection probability (0.80) when `known_absent` has no per-species values |
| `score_sharpness` | Controls likelihood discrimination; higher = more weight on score differences; 0 = uniform likelihood |
| `prior_phi` | Named numeric vector mapping `information_quality` → Beta concentration (phi = alpha + beta). Default `c(high = 50, moderate = 10, low = 3)`. Scalar = uniform phi. NULL = fixed priors (no Beta sampling). |
| `prior_weight_guide` | Named list of 7 prior weight ranges guiding LLM assignments. Each element is `c(min, max)`. Keys: `native_expected`, `native_occasional`, `native_unlikely`, `nearby_expected`, `nearby_occasional_unlikely`, `not_documented`, `taxonomically_impossible`. Defaults reproduce Session 45 ranges. Customize for different ecosystems or taxonomic groups. |
| `n_sims` | Monte Carlo simulations for `compute_posterior()`. Default 1000 (changed from 0 in Session 47). |

**LLM prior prompt** asks for `range_status` + `habitat_fit` + `information_quality` + `prior_weight` per taxon.
`habitat_fit` values: `"expected"`, `"occasional"`, `"unlikely"`.
`information_quality` values: `"high"`, `"moderate"`, `"low"` — reflects how much published data
exists about the taxon's distribution in the focal region (NOT confidence in the weight itself).
Mapped to phi via `prior_phi`; alpha = prior_mean × phi, beta = (1 − prior_mean) × phi.
Prior weight scale integrates both dimensions: native+expected = 0.5–1.0; native+unlikely = 0.003–0.03.
Now user-customizable via `prior_weight_guide` parameter (Session 57).
`ctx$main_habitat` (renamed from `ctx$habitat`) is the recognized context field for site habitat;
in the full pipeline this should be populated from the `main_habitat` column produced by TaxaHabitat.
When `known_present`/`known_absent` are supplied, a "Survey context" block is prepended.

**Internal helpers:** `.score_to_likelihood()`, `.build_group_map()`, `.collect_unique_taxa()`,
`.get_group_context()`, `.build_taxa_prompt()`, `.parse_taxa_response()`.

**Family-level unreferenced taxon insertion** (in `.score_to_likelihood()`): activated when `unreferenced_taxa` carries
an `unreferenced_family` attribute (from `suggest_unreferenced_species(expand_to_family=TRUE)`). Inserts
species whose genus is absent from candidates but whose family is represented; likelihood
proxy = median exp-score of all candidates in that family.

---

## Function Signature: `posterior_consensus()` (formerly `consensus_taxonomy()`)

```r
posterior_consensus(posterior_df,
                    rank_system             = NULL,
                    cumulative_threshold    = 0.9,
                    min_posterior           = 0.05,
                    posterior_col           = "posterior_mean",
                    lookup_missing_taxonomy = FALSE,
                    backbone_id             = 11L,
                    species_reference       = NULL)
```

**Output:** one row per `observation_id` with columns: `consensus_taxon`, `consensus_rank`,
`consensus_reason`, `is_resolved`, `consensus_posterior`, `consensus_confidence_score`,
`n_plausible`, `winner_prior`, `winner_likelihood`, `winner_likelihood_cov`,
`plausible_taxa` (list), `plausible_posteriors` (list).
`consensus_reason` values: `"unanimous"` (all plausible agree at finest rank), `"single"`
(only one plausible hypothesis), `"lca"` (multiple plausible, LCA at coarser rank), or `NA`.
`winner_prior` = `prior_mean` of highest-posterior hypothesis; `winner_likelihood` =
`score_likelihood`; `winner_likelihood_cov` = `score_likelihood_cov`. All three are `NA`
when the source column is absent (e.g. `assign_taxa_llm()` input) or consensus is `NA`.
Use these columns with `TaxaFlag::flag_prior_mismatch()` to detect implausible winners
(e.g. a low-prior taxon winning due to a reference error or sequencer 100%-rule artefact).
When `result2` from `update_prior_from_consensus()` is passed as input, also adds:
`prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1`, `taxon_changed`.
When `species_reference` is non-NULL, also adds: `downranked` (logical).

**LCA logic:** all named hypotheses contribute (`specific_candidate`, `unreferenced_species`,
`unreferenced_genus`); only `unreferenced_family` catch-all (NA taxon_name) is excluded. Plausible set = top
hypotheses summing to `cumulative_threshold` of named-taxon mass, after dropping any below
`min_posterior`. Genus is derived from binomial when explicit column has NA (e.g. unreferenced rows).
`lookup_missing_taxonomy = TRUE` calls `TaxaTools::verify_taxon_names()` + `change_backbone()`
to fill family/genus/species for unreferenced rows. `backbone_id` passed through (default 11 = GBIF).

**Renormalization note:** cumulative proportions are renormalized (post-`min_posterior` filter)
only for selecting the plausible set. The reported `consensus_posterior` is the raw sum of
posteriors within the LCA taxon from all named hypotheses (pre-filter), so it is never inflated.

**`species_reference` (downranking):** after LCA, unresolved coarse-rank rows are downranked
when the reference contains exactly one finer taxon at each step (recursive: family → genus →
species in one pass if unambiguous at each step). Accepts either a `taxaexpect_species_df`
data.frame (Bayesian workflow) or an `unreferenced_species_result` object (LLM workflow —
uses `attr(x, "plausible")`, which includes referenced species the LLM flagged as plausible).
Conservative: stops at any rank with >1 option. `downranked = TRUE` flags changed rows.

**Internal helpers:** `.consensus_one_sample()`, `.find_lca()`, `.extract_rank_values()`,
`.empty_consensus_row()`, `.build_species_ref()`, `.downrank_consensus()`.

---

## Function Signature: `score_consensus()`

```r
score_consensus(match_df,
                min_score       = 0,
                max_gap         = Inf,
                rank_thresholds = NULL,
                whitelist       = NULL,
                score_col       = "score_original",
                rank_system     = NULL)
```

**Output:** one row per `observation_id` with columns: `consensus_taxon`, `consensus_rank`,
`consensus_reason`, `is_resolved`, `top_score`, `n_retained`, `n_taxa`, `retained_taxa` (list).
`consensus_reason` values: `"unanimous"`, `"single"`, `"lca"`, `"threshold"` (rank_thresholds demoted), or `NA`.
When `rank_thresholds` is non-NULL, also adds: `rank_capped` (logical).
When `whitelist` is non-NULL, also adds: `whitelist_capped` (logical).

**Algorithm:** (1) discard hits below `min_score`; (2) keep hits within `max_gap` of
top score per sample; (3) LCA of retained hits; (4) cap rank by `rank_thresholds`
(finest rank whose threshold the top score meets); (5) uprank to whitelist if consensus
taxon absent.

**Conventional eDNA thresholds (GITA / Jonah Ventures):**
`rank_thresholds = c(species = 98, genus = 95, family = 90, order = 85)`

**Reuses** `.find_lca()` and `.extract_rank_values()` from `posterior_consensus.R`.

**Internal helpers:** `.score_consensus_one()`, `.cap_rank_by_threshold()`,
`.uprank_to_whitelist()`.

---

## Function Signature: `update_prior_from_consensus()`

```r
update_prior_from_consensus(result,
                             consensus,
                             presence_multiplier = 5,
                             n_sims              = 0)
```

One-pass empirical Bayes refinement. Extracts `is_resolved = TRUE` species from `consensus`
as confirmed-present evidence; multiplies their `prior_mean` by `presence_multiplier` in all
unresolved samples; re-runs `compute_posterior()` on those samples only. Resolved samples are
returned unchanged. Also joins `consensus_taxon_v1` / `consensus_rank_v1` / `prior_updated`
columns into the returned dataframe for downstream propagation by `posterior_consensus()`.

**Circularity guard:** a sample's own posterior never feeds back into its own prior — only
other samples' confirmations are used.

---

## Function Signature: `build_context()`

```r
build_context(taxon_names,
              geographic_hint = NULL,
              date            = NULL,
              habitat_scheme  = NULL,
              llm_fn          = TaxaTools::call_anthropic_api,
              chunk_size      = 60L)
```

Auto-populates the `context` argument for `assign_taxa_llm()` from a list of candidate taxon
names. Requires TaxaHabitat (in Suggests).

**Pipeline:** `build_habitat_prompt()` → `llm_fn()` per chunk → `parse_hierarchical_habitat_response()`
→ `consensus_habitat()` → short LLM synthesis call → one-row `ctx` data frame.

The synthesis call asks the LLM to describe the likely sampling habitat from the habitat
proportions + species list in 3-8 words. This produces more informative labels for transitional
environments (e.g. "coastal lagoon / estuary") than the mechanical argmax of habitat weights.
Falls back to the consensus argmax if synthesis parsing fails.

**Output:** one-row data frame with `ecoregion`, `main_habitat`, `date`.
`attr(ctx, "habitats_df")` = per-species habitat weight table.
`attr(ctx, "habitat_proportions")` = named numeric vector of habitat proportions.

**Internal helpers:** `.build_synthesis_prompt()`, `.parse_synthesis_response()`.

---

## Interface Contract

This is the confirmed column contract between TaxaAssign and its upstream packages.
TaxaMatch must produce these columns; TaxaExpect prior output maps as noted.

### Likelihood Object (from TaxaMatch — not yet built)

| Column | Type | Notes |
|---|---|---|
| `observation_id` | character | Unique observation identifier |
| `score_likelihood` | numeric | Point estimate likelihood |
| `score_likelihood_mean` | numeric | Mean of likelihood distribution |
| `score_likelihood_sd` | numeric | SD of likelihood distribution |

### Prior Object (from TaxaExpect `generate_full_priors()`)

TaxaExpect outputs `taxon_name`, `alpha`, `beta`, `theta_mean`, `theta_sd`.
`join_priors()` maps these to `compute_posterior()` columns:

| TaxaExpect column | Maps to | Notes |
|---|---|---|
| `alpha` | `prior_alpha` | Beta shape1; passed through via `coalesce(alpha, dark_alpha)` |
| `beta` | `prior_beta` | Beta shape2; passed through via `coalesce(beta, dark_beta)` |
| `theta_mean` | `prior_mean` | Derived: `prior_alpha / (prior_alpha + prior_beta)` |
| `taxon_name` | must join on `label` or equivalent | — |

`join_priors()` handles the likelihood–prior join, aligning on `observation_id` × taxon label
with dark diversity fallback for taxa without model predictions.

### Posterior Object (output of `compute_posterior()`)

All input columns preserved, plus: `posterior_point_est`, `posterior_mean`,
`posterior_sd`, `confidence_score`.

---

## Developer Workflow — When to Run What

| Situation | Command | Speed |
|---|---|---|
| Editing code, running `devtools::test()` inside the package | Nothing extra — `load_all()` is implicit | Fast |
| Changed roxygen docs or added/removed exports | `devtools::document()` | Fast |
| Need to use the package from another project (`library(TaxaAssign)`) | `devtools::install()` | Slow |
| Stale namespace / unexplained errors after switching branches | Restart R, then `library(TaxaAssign)` | Medium |

**Rule:** `document()` is enough when staying inside the package. `install()` is only needed when crossing the package boundary into a workflow script or another package.

---

## Key Design Notes

- Native pipe `|>` used throughout (magrittr removed from Imports in Session 37)
- S3 dispatch (`compute_posterior.point()`, `.parametric()`, `.sampled()`) is documented
  in a comment but **not implemented** — current function handles all paths internally
- `normalize_vec()` is an embedded helper (not `@noRd` tagged, but acceptable as private)
- `confidence_score` without simulation: set to 1 for the winning hypothesis, 0 for others
  (binary, not fractional)

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-compute_posterior.R | `compute_posterior()` | 12 tests: Beta prior, uncertainty propagation, MC, n_sims=0, NA handling, sort order |
| test-assign_taxa_llm.R | `assign_taxa_llm()` | LLM calls mocked |
| test-build_context.R | `build_context()` | Fully offline |
| test-expand_unreferenced.R | `expand_unreferenced_hypotheses()` | Fully offline |
| test-generate_report.R | `generate_report()` | Fully offline |
| test-integration.R | Full pipeline integration | Uses minimal fixtures |
| test-join_priors.R | `join_priors()` | Fully offline |
| test-posterior_consensus.R | `posterior_consensus()` | Includes winner_prior/winner_likelihood/winner_likelihood_cov columns (Session 101) |
| test-report_assign.R | `report_assign()` | Fully offline |
| test-run_pipelines.R | `run_bayesian_pipeline()`, `run_llm_pipeline()` | Mocked LLM |
| test-score_consensus.R | `score_consensus()` | Fully offline |
| test-suggest_unreferenced_species.R | `suggest_unreferenced_species()` | LLM mocked |
| test-update_prior.R | `update_prior_from_consensus()` | Fully offline |

---

## Dependencies

| Package | Used for |
|---|---|
| cli | `cli_abort()`, `cli_warn()`, `cli_inform()` for user-facing messages |
| dplyr | `group_split()`, `arrange()`, `n_distinct()` |
| purrr | `map_dfr()` to apply over `observation_id` groups |
| stats | `rnorm()`, `rbeta()`, `sd()`, `setNames()`, `median()` for Monte Carlo and likelihood helpers |
| rlang | `.data` pronoun |
| TaxaTools | `verify_taxon_names()` + `change_backbone()` (Suggests; used only when `lookup_missing_taxonomy = TRUE`) |
| TaxaHabitat | `build_habitat_prompt()`, `parse_hierarchical_habitat_response()`, `consensus_habitat()` (Suggests; used only by `build_context()`) |

---

## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `calculate_final_posteriors` | `compute_posterior` | 2026-02-19 | — |
| `prior_df` | `likelihood_w_prior` | 2026-02-19 | Input dataframe |
| `Query_ID` | `observation_id` | 2026-02-19 | — |
| `LR_PointEst` | `score_likelihood` | 2026-02-19 | — |
| `LR_Mean` | `score_likelihood_mean` | 2026-02-19 | — |
| `LR_SD` | `score_likelihood_sd` | 2026-02-19 | — |
| `Prior_Prob` | `prior_mean` | 2026-02-19 | — |
| `Posterior_Mean` | `posterior_mean` | 2026-02-19 | — |
| `Posterior_SD` | `posterior_sd` | 2026-02-19 | — |
| `Posterior_PointEst` | `posterior_point_est` | 2026-02-19 | — |
| `Confidence_Score` | `confidence_score` | 2026-02-19 | — |
| `ghost` (bool column) | `hypothesis_type` (character) | 2026-03-30 | Values: "specific_candidate" / "unreferenced_species" / "unreferenced_genus" |
| `habitat_affinity` | `habitat_fit` | 2026-03-30 | LLM categorical: "expected"/"occasional"/"unlikely"; distinct from TaxaHabitat's numeric habitat weights |
| `missing_species` | `unreferenced_species` | 2026-03-30 | `hypothesis_type` value; species absent from reference DB but described |
| `missing_genus` | `unreferenced_genus` | 2026-03-30 | `hypothesis_type` value; family-level unreferenced taxon or uncharacterised diversity |
| `ctx$habitat` | `ctx$main_habitat` | 2026-03-30 | Recognized context field in `assign_taxa_llm()`; aligns with TaxaHabitat/TaxaExpect column |
| `Main_Habitat` | `main_habitat` | 2026-03-30 | Site-level habitat column; ecosystem-wide rename for snake_case consistency |
| `prior_sd` (Normal) | `prior_alpha`/`prior_beta` (Beta) | 2026-04-04 | `compute_posterior()` now samples priors from Beta(alpha, beta); `prior_sd` removed. `assign_taxa_llm()` maps `information_quality` → phi → alpha/beta. `join_priors()` passes TaxaExpect alpha/beta directly. |

---

## Session Notes

Sessions 29–77 archived in ecosystem_docs/session_notes/TaxaAssign_sessions.md.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename across all 13 R source files, 12 test files, 2 vignettes,
  5 inst/ files, dev/ files, and README. Largest package: ~361 occurrences.
- `sample_meta` → `event_meta` throughout (variable name for L1 collection event metadata)
- `globalVariables("sample_id")` → `globalVariables("observation_id")` in `R/assign_taxa_llm.R`
- `generate_report.R`: prose changed from "samples" to "observations" in `.build_results_template()`
- Required reinstalling TaxaMatch, TaxaLikely, TaxaFlag for cross-package `filter_redundant_hypotheses()` calls
- 412 tests passing (4 warnings, 1 skip — pre-existing)

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaAssign-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), model
  registry enhancements, WERC peer review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `.resolve_llm_fn()` in `R/site_utils.R`: fallback updated from `TaxaTools::call_anthropic_api`
  to `TaxaTools::call_api`. Covers `assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`,
  `suggest_unreferenced_species()`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

**Session 99 (2026-06-02)**
- Column renames (breaking — ecosystem-wide):
  - `score` → `score_original`: `score_consensus()` default `score_col` updated; all tests and
    workflows updated; `TaxaAssign_llm_workflow.R` had 3 missed `$score` / `score_col="score"`
    references fixed during workflow testing
  - `likelihood_point_est`/`_mean`/`_sd` → `score_likelihood`/`_mean`/`_sd`: all R source,
    tests, inst/ files updated
  - `"unknown_species"` hypothesis_type → `"unreferenced_family"` with `NA` `taxon_name`:
    `assign_taxa_llm.R` updated; `posterior_consensus.R` filter changed from
    `taxon_name == "unknown_species"` to `is.na(taxon_name)`;
    `TaxaAssign_supplemental_methods.md` updated throughout
- `assign_taxa_llm.R` bug fix: column collision guard added before `dplyr::left_join()`
  (prior_df columns `hypothesis_type`/`taxon_name_rank` caused `.x`/`.y` split, making
  `merged$hypothesis_type` NULL); `unk_idx` changed from
  `merged$hypothesis_type == "unreferenced_family"` to `is.na(merged$taxon_name)` (more robust)
- Test fixes: 6 assertions in `test-assign_taxa_llm.R` gained `!is.na(result$taxon_name) &`
  guards (NA comparison `NA == "..."` returns NA, not FALSE, causing spurious row inclusion)
- Workflows: `TaxaAssign_bayesian_workflow.R` and `TaxaAssign_llm_workflow.R` updated for
  all column renames; workflow testing confirmed all stages pass with real data

**Session 89 (2026-05-27)**
- `suggest_unreferenced_species()`: `data_type` param added (`"eDNA"` default / `"acoustic"` / `"image"`). eDNA path: existing NCBI nucleotide count queries. Acoustic/image path: set-membership check against `reference_species` (character vector of classifier's known species list). LLM prompt `ref_filter_note` switches text accordingly via `switch(data_type, ...)`. `barcode_term`, `max_date`, and `rentrez` requireNamespace guard now all wrapped in `if (data_type == "eDNA")`. `reference_species` param added (required for acoustic/image; ignored for eDNA).

