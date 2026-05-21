# CLAUDE.md — TaxaAssign
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-20 (Session 79 — sample_id → observation_id rename; event_meta replaces sample_meta)

---

## Package Purpose
Implements Bayesian taxonomic assignment by combining likelihood and prior objects to
compute posterior probabilities. Final step in the TaxaID pipeline. Designed to accept
any conforming likelihood and prior objects — inputs may come from TaxaMatch/TaxaExpect
or be user-supplied from outside the ecosystem.

**Status: Twelve working functions (9 core + 3 wrappers/utilities). All planned functions removed — superseded by inline workflow logic or existing function internals.**

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
| `compute_posterior()` | Core Bayes update: likelihood × prior → posterior | Complete | R/compute_posterior.R |
| `expand_unreferenced_hypotheses()` | Replace generic H2/H3 rows from TaxaLikely with named unreferenced species; bridges TaxaLikely likelihoods to TaxaExpect priors | Complete | R/expand_unreferenced.R |
| `suggest_unreferenced_species()` | LLM-first unreferenced species detection: plausible species per genus → NCBI barcode count → unreferenced vector; optional family expansion | Complete | R/suggest_unreferenced_species.R |
| `assign_taxa_llm()` | LLM-shortcut pipeline: score-based likelihoods + LLM priors → posteriors | Complete | R/assign_taxa_llm.R |
| `posterior_consensus()` | LCA-based consensus from posterior dataframe; one row per `observation_id` | Complete | R/posterior_consensus.R |
| `score_consensus()` | Conventional score-based consensus (min_score, max_gap, rank_thresholds, whitelist); one row per `observation_id` | Complete | R/score_consensus.R |
| `update_prior_from_consensus()` | Boost priors for confirmed species in unresolved samples; re-run `compute_posterior()` | Complete | R/update_prior_from_consensus.R |
| `build_context()` | Auto-populate `ctx` (ecoregion, main_habitat, date) from taxon names via TaxaHabitat + LLM synthesis | Complete | R/build_context.R |
| `generate_report()` | Publication-ready Methods + Results text; hybrid template (Methods) + LLM (Results) with template fallback | Complete | R/generate_report.R |
| `join_priors()` | Bridge likelihoods to priors: join TaxaExpect priors with dark diversity fallback, fill taxonomy, filter redundant hypotheses. `site` requires `main_habitat` — accepts `list(lat, lon, main_habitat)` or `list(grid_id, main_habitat)` or multi-site data frame. Modelled species with habitat-mismatch priors promoted to dark diversity floor. | Complete | R/join_priors.R |
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
| `likelihood_point_est` | numeric | Point estimate of likelihood for this hypothesis |
| `likelihood_mean` | numeric | Mean of likelihood distribution |
| `likelihood_sd` | numeric | SD of likelihood distribution (NA → replaced with 0 + warning) |
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
- **Point estimate path** — always runs; uses `likelihood_point_est` and `prior_mean`
- **Monte Carlo path** — runs only when `n_sims > 0` AND at least one source of uncertainty exists (non-zero `likelihood_sd`, or `prior_alpha`/`prior_beta` present). Likelihoods sampled from `Normal(mean, sd)` floored at 0; priors sampled from `Beta(alpha, beta)`.

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
`habitat_fit`, `information_quality`, `likelihood_point_est`, `likelihood_mean`, `likelihood_sd`,
`prior_mean`, `prior_alpha`, `prior_beta`, `posterior_point_est`, `posterior_mean`, `posterior_sd`,
`confidence_score`. Taxonomy columns from `match_df` (e.g. `family`, `genus`, `species`)
are carried through via `rank_system` detection and used by `consensus_taxonomy()`.
`hypothesis_type` values: `"specific_candidate"`, `"unreferenced_species"` (congener without barcode reference),
`"unreferenced_genus"` (family-level unreferenced taxon or uncharacterised diversity).
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
`n_plausible`, `plausible_taxa` (list), `plausible_posteriors` (list).
`consensus_reason` values: `"unanimous"` (all plausible agree at finest rank), `"single"`
(only one plausible hypothesis), `"lca"` (multiple plausible, LCA at coarser rank), or `NA`.
When `result2` from `update_prior_from_consensus()` is passed as input, also adds:
`prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1`, `taxon_changed`.
When `species_reference` is non-NULL, also adds: `downranked` (logical).

**LCA logic:** all named hypotheses contribute (`specific_candidate`, `unreferenced_species`,
`unreferenced_genus`); only `unknown_species` catch-all is excluded. Plausible set = top
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
                score_col       = "score",
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
| `likelihood_point_est` | numeric | Point estimate likelihood |
| `likelihood_mean` | numeric | Mean of likelihood distribution |
| `likelihood_sd` | numeric | SD of likelihood distribution |

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

| File | Status |
|---|---|
| `tests/testthat/test-compute_posterior.R` | 12 tests: Beta prior structure, uncertainty propagation, fixed-prior fallback, MC with likelihood-only uncertainty, n_sims=0, missing columns, NA handling, single-hypothesis, sort order, alpha/beta validation, high-vs-low phi |
| `dev/test_compute_posterior.R` | 6 legacy manual tests (pre-Beta refactor; not wired into testthat) |

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
| `LR_PointEst` | `likelihood_point_est` | 2026-02-19 | — |
| `LR_Mean` | `likelihood_mean` | 2026-02-19 | — |
| `LR_SD` | `likelihood_sd` | 2026-02-19 | — |
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

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename across all 13 R source files, 12 test files, 2 vignettes,
  5 inst/ files, dev/ files, and README. Largest package: ~361 occurrences.
- `sample_meta` → `event_meta` throughout (variable name for L1 collection event metadata)
- `globalVariables("sample_id")` → `globalVariables("observation_id")` in `R/assign_taxa_llm.R`
- `generate_report.R`: prose changed from "samples" to "observations" in `.build_results_template()`
- Required reinstalling TaxaMatch, TaxaLikely, TaxaFlag for cross-package `filter_redundant_hypotheses()` calls
- 412 tests passing (4 warnings, 1 skip — pre-existing)
