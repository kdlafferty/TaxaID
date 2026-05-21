# TaxaID Jargon Audit

**Prompt 1 of POLISHING_ROADMAP.md**
**Date:** 2026-04-12 (Session 55)
**Scope:** All 7 packages — R source files, tests, workflow scripts, CLAUDE.md files

---

## How to Read This Document

**Section 1** lists cross-package inconsistencies that need fixing: the same concept
referred to by different names, the same term meaning different things, or terms used
without adequate definition. These are the high-priority items for Prompt 9.

**Section 2** lists terms that are internally consistent but would confuse a new user
because they lack a clear, accessible definition at point of use.

**Section 3** is a compact glossary of all ecosystem-specific terms for reference.

---

## Section 1: Cross-Package Inconsistencies

### 1.1 Same Concept, Different Parameter Names

| Concept | TaxaTools param | TaxaMatch param | TaxaLikely param | TaxaAssign param | Suggested standard |
|---|---|---|---|---|---|
| Ordered rank vector (coarse → fine) | `taxonomy_ranks` | `rank_order` | `rank_system` | `rank_system` | `rank_system` everywhere |
| Raw match quality metric | — | `score` (col), `pident` (BLAST) | `p_match` (0-1), `score` (input col) | `score` (input col) | `score` as user-facing; `p_match` internal to TaxaLikely only |
| Unique query identifier | — | `asv_id` (pre-std), `sample_id` (post-std) | `sample_id` | `sample_id` | Consistent; document that `asv_id` is pre-standardization only |

**Priority: HIGH** — `taxonomy_ranks` vs `rank_order` vs `rank_system` is the most
confusing inconsistency. A user who learns the term in one package must relearn it in
another. Recommend standardizing to `rank_system` (already used in 2 of 3 packages)
and aliasing the old names with deprecation warnings.

### 1.2 Same Term, Different Meanings

| Term | Package | Meaning | Risk |
|---|---|---|---|
| **score** | TaxaTools (`verify_taxon_names`) | API confidence (0-1) for name match against backbone | LOW — different domain (name verification vs sequence matching) |
| **score** | TaxaMatch/TaxaLikely/TaxaAssign | Raw match quality (% identity, similarity) | — |
| **singleton** | TaxaLikely | Reference sequence with no within-species neighbors | MED — same ecosystem, different meaning |
| **singleton** | TaxaExpect | Species observed exactly once across all samples | MED |
| **phi** | TaxaExpect (`generate_full_priors`) | Beta precision = alpha + beta | LOW — same math concept, different context |
| **phi** | TaxaAssign (`prior_phi` in `assign_taxa_llm`) | Beta concentration mapped from `information_quality` | LOW |
| **prompt** | TaxaTools (`draft_methods_text`) | Plain character string sent to LLM | MED — type mismatch could confuse developers |
| **prompt** | TaxaFetch/TaxaHabitat | S3 object (`llm_prompt`, `habitat_prompt`) with chunks | MED |

**Priority for "singleton":** HIGH — Both meanings appear in the same ecosystem and a
user reading TaxaExpect documentation after TaxaLikely will be confused. Recommend
renaming TaxaExpect's concept to something more specific (e.g., `single_detection` or
keeping `singleton` but always qualifying: "singleton species" vs "singleton sequence").

**Priority for "prompt":** MEDIUM — The type inconsistency (string vs S3 object) is
already handled by the `llm_fn` abstraction layer, but the term overloading should be
acknowledged in documentation. No rename needed.

### 1.3 Synonym Pairs (Different Terms for Same Concept)

| Concept | Term A | Where | Term B | Where | Suggested fix |
|---|---|---|---|---|---|
| Species not in reference DB | `unreferenced` | TaxaLikely, TaxaAssign | `missing` (in code comments, GITA) | scattered comments | Ensure `unreferenced` is used everywhere; grep for "missing species" in comments |
| Mislabeled reference sequence | `mislabeled` | TaxaLikely (formal) | `traitor` | TaxaLikely (informal, in `traitor_threshold` param) | Document that "traitor" is the informal shorthand; consider renaming `traitor_threshold` → `mislabel_threshold` |
| Unobserved species prior | `dark_diversity` | TaxaAssign (`join_priors`) | `undetected_diversity` | TaxaExpect (`generate_undetected_diversity`) | Both are legitimate ecological terms but used for slightly different scopes. Document the distinction: `undetected_diversity` = TaxaExpect Tier 3 proxies; `dark_diversity` = TaxaAssign fallback prior derived from those proxies |
| Taxonomic hierarchy path | `classification_path` | TaxaTools | `lineage` | TaxaMatch, TaxaLikely | Different scopes: `classification_path` is pipe-delimited string from API; `lineage` is the conceptual hierarchy. No rename needed but document the distinction |

### 1.4 Residual "Ghost" Terminology

The Session 39 rename from "ghost" to "unreferenced" was extensive but check for
remnants in comments and documentation:

| Location to check | What to look for |
|---|---|
| All CLAUDE.md files | `ghost` in session notes (historical, OK to keep) |
| `TaxaAssign/inst/PRIOR_LIKELIHOOD_MATCHING.md` | "Ghost prior values" heading (flagged Session 40, not yet renamed) |
| Code comments across all packages | `ghost` used as synonym for `unreferenced` |
| `suggest_unreferenced_species.R` | Internal variable names (should be clean after Session 39) |

---

## Section 2: Terms Needing Better User-Facing Documentation

These terms are used consistently but lack clear definitions accessible to a new user
(e.g., in roxygen `@details`, a glossary vignette, or inline comments).

### 2.1 Statistical Concepts (TaxaLikely / TaxaAssign)

| Term | Where used | Current documentation | What's missing |
|---|---|---|---|
| **H1 / H2 / H3** | TaxaLikely (everywhere) | CLAUDE.md, methods_background.md | No roxygen-level plain-English explanation visible to `?evaluate_likelihoods` user |
| **score_logit / gap_logit** | TaxaLikely train.R, evaluate.R | Inline code comments | No user-facing explanation of what logit transform does and why it matters |
| **taxonomy_code_a** | TaxaLikely train.R | None | Cryptic internal name from UBC source; rename to `finest_rank_col` or similar |
| **shrinkage / prior_weight** | TaxaLikely train.R | Brief roxygen | Need `@details` explaining Empirical Bayes shrinkage concept for non-statisticians |
| **anchor_perfect** | TaxaLikely train.R | Good roxygen | Mention "perfection penalty" problem it solves in `@details` |
| **delta** | TaxaLikely (H2/H3 offsets) | CLAUDE.md only | Needs roxygen explanation: "logit-scale shift from H1 mean representing expected score reduction for unreferenced taxa" |
| **dark_diversity** | TaxaAssign join_priors.R | Brief roxygen | Ecological concept unfamiliar to most users; needs 1-2 sentence explanation |
| **cumulative_threshold** | TaxaAssign posterior_consensus.R | Good roxygen | Could benefit from example: "at 0.9, the plausible set includes the fewest hypotheses whose posteriors sum to at least 90%" |
| **score_sharpness** | TaxaAssign assign_taxa_llm.R | Roxygen present | Non-obvious effect; needs `@details` with example of how different values change results |
| **information_quality** | TaxaAssign assign_taxa_llm.R | Roxygen present | Clarify this is LLM's self-assessment of data availability, not confidence in the assignment |

### 2.2 Ecological Concepts (TaxaHabitat / TaxaExpect)

| Term | Where used | What's missing |
|---|---|---|
| **theta** | TaxaExpect (central concept) | Needs plain-English definition in roxygen: "the probability that a randomly sampled individual from the community at a site belongs to species X" |
| **Tier 1 / Tier 2 / Tier 3** | TaxaExpect train_biodiversity_model.R | Well-defined internally but not in ecosystem CLAUDE.md; users who start with TaxaAssign won't know what tiers mean when they see `undetected_type` |
| **observed_in_habitat** | TaxaExpect prepare_model_dataframe.R | Renamed from `habitat_observed_elsewhere` (Session 81). TRUE = species recorded in this habitat type during training; FALSE = habitat extrapolation |
| **physical_zone** | TaxaHabitat flag_habitat_inconsistencies.R | Internal derived column; explain derivation logic for users reviewing spatial flags |
| **realm** | TaxaHabitat | IUCN ecological realm; explain valid values and how they're used |

### 2.3 Data Pipeline Concepts (TaxaFetch / TaxaMatch)

| Term | Where used | What's missing |
|---|---|---|
| **col_map** | TaxaTools, TaxaMatch, TaxaFetch | Well-documented per-package but no ecosystem-level explanation of the pattern |
| **match object** | TaxaMatch (conceptual) | Defined in CLAUDE.md but not in a roxygen `@details` accessible via `?standardize_match_data` |
| **bio_score** | TaxaFetch dataone_occurrence_search.R | Scoring heuristic needs explanation of what keywords contribute and their weights |
| **RID** | TaxaMatch blast.R | NCBI-specific; add brief "(Request ID from NCBI BLAST API)" at first use |

---

## Section 3: Compact Ecosystem Glossary

Organized by domain. ~150 terms across 7 packages.

### Taxonomic Identity & Naming

| Term | Definition | Primary package(s) |
|---|---|---|
| `taxon_name` | Most specific non-NA rank value for a row; derived by `create_taxon_names()` | TaxaTools (origin), all packages |
| `taxon_name_rank` | Lowercase rank label of `taxon_name` (e.g., "species", "genus") | TaxaTools (origin), all packages |
| `taxonomy_ranks` / `rank_system` / `rank_order` | Ordered character vector of rank names, coarsest first | TaxaTools / TaxaLikely+TaxaAssign / TaxaMatch |
| `classification_path` | Pipe-delimited hierarchical taxonomy string from backbone API | TaxaTools |
| `classification_ranks` | Pipe-delimited rank labels aligned with `classification_path` | TaxaTools |
| `backbone_id` | Integer ID for target taxonomic database (1=CoL, 3=ITIS, 4=NCBI, 9=WoRMS, 11=GBIF) | TaxaTools |
| `matched_name` | Best-matched name from backbone API | TaxaTools |
| `verified` | Logical: did the API return a successful result? | TaxaTools |
| `col_map` | Named character vector mapping source column names to target names | TaxaTools, TaxaMatch, TaxaFetch |
| `DarwinCore` / `DwC` | International standard for biodiversity data column names | TaxaTools, TaxaFetch |
| `scientificName` | DwC column: formal binomial species name | TaxaFetch |

### Sequence Matching (TaxaMatch)

| Term | Definition | Primary package(s) |
|---|---|---|
| `sample_id` | Canonical unique identifier for a query (post-standardization) | TaxaMatch (origin), TaxaLikely, TaxaAssign |
| `asv_id` | Amplicon Sequence Variant identifier (pre-standardization) | TaxaMatch |
| `ESV` | Environmental Sequence Variant; synonym for ASV in some pipelines | TaxaMatch |
| `score` | Raw match quality metric (e.g., percent identity 0-100) | TaxaMatch, TaxaLikely, TaxaAssign |
| `match_df` / `match object` | Standardized data frame: one row per sample_id x candidate taxon | TaxaMatch (origin), TaxaLikely |
| `pident` | Percent identity from BLAST output (0-100) | TaxaMatch |
| `qcovs` | Query coverage percentage from BLAST | TaxaMatch |
| `slen` | Subject (reference) sequence length in bp | TaxaMatch |
| `evalue` | BLAST E-value: statistical significance of alignment | TaxaMatch |
| `bitscore` | BLAST bit score: normalized alignment score | TaxaMatch |
| `barcode_term` | Molecular marker identifier (e.g., "12S", "COI", "MiFish") | TaxaMatch, TaxaLikely |
| `score_range` | Window size: keep hits within X% of top hit per query (default 2) | TaxaMatch |
| `min_score` | Minimum percent identity threshold (default 70) | TaxaMatch |
| `min_query_coverage` | Minimum query coverage threshold (default 80) | TaxaMatch |
| `max_hits` | Per-query hit cap after filtering (default 20) | TaxaMatch |
| `RID` | Request ID from NCBI BLAST URL API | TaxaMatch |
| `accession` | GenBank/RefSeq accession number | TaxaMatch, TaxaLikely |
| `filter_redundant_hypotheses` | Remove coarser-rank rows superseded by finer-rank rows in same lineage | TaxaMatch |
| `lineage` | Complete taxonomic hierarchy from kingdom to species | TaxaMatch, TaxaLikely |

### Likelihood Model (TaxaLikely)

| Term | Definition | Primary package(s) |
|---|---|---|
| `H1` | Known species hypothesis: query from a species in the reference DB | TaxaLikely |
| `H2` | Missing species hypothesis: query from unreferenced species in a represented genus | TaxaLikely |
| `H3` | Missing genus hypothesis: query from an entirely absent genus | TaxaLikely |
| `hypothesis_type` | Categorical column: "specific_candidate", "unreferenced_species", "unreferenced_genus" | TaxaLikely (origin), TaxaAssign |
| `specific_candidate` | hypothesis_type value: referenced species with explicit match | TaxaLikely, TaxaAssign |
| `unreferenced_species` | hypothesis_type value: species absent from reference (H2) | TaxaLikely, TaxaAssign |
| `unreferenced_genus` | hypothesis_type value: genus absent from reference (H3) | TaxaLikely, TaxaAssign |
| `unknown_species` | hypothesis_type value: uncharacterised diversity catch-all (TaxaAssign only) | TaxaAssign |
| `unresolved_species` | hypothesis_type value: ambiguous among referenced members of complete genus | TaxaAssign |
| `score_logit` | Logit-transformed normalized match score | TaxaLikely |
| `gap_logit` | Best within-taxon logit score minus best cross-taxon logit score | TaxaLikely |
| `p_match` | Match score on 0-1 scale (1 - distance) | TaxaLikely |
| `likelihood_point_est` | Deterministic likelihood ratio (normalized so max = 1.0) | TaxaLikely, TaxaAssign |
| `likelihood_mean` | Monte Carlo mean likelihood | TaxaLikely, TaxaAssign |
| `likelihood_sd` | Standard deviation of likelihood from MC simulations | TaxaLikely, TaxaAssign |
| `taxa_model_params` | S3 class for trained likelihood model | TaxaLikely |
| `H1_Lookup` | Per-species parameters: mu_score, mu_gap, sigma_score | TaxaLikely |
| `H1_Global_Mu` | Global fallback means (score_logit, gap_logit) | TaxaLikely |
| `H1_Sigma` | Global 2x2 covariance matrix | TaxaLikely |
| `delta` | Logit-scale offset between hypothesis means (H2 ~3.0, H3 ~5.0) | TaxaLikely |
| `shrinkage` | Empirical Bayes weight-averaging toward global mean | TaxaLikely |
| `prior_weight` | Hyperparameter controlling shrinkage strength (default 10.0) | TaxaLikely |
| `anchor_perfect` | Flag: inject synthetic perfect-match pseudo-data | TaxaLikely |
| `taxonomy_code_a` | Internal: finest rank column label (cryptic; from UBC source) | TaxaLikely |
| `singleton` | (TaxaLikely) Reference sequence with no within-species neighbors | TaxaLikely |
| `mislabeled` / `traitor` | Reference sequence matching foreign species better than own label | TaxaLikely |
| `reference_df` | Data frame: composite_id, sequence, taxonomy columns | TaxaLikely |
| `census` | Per-genus summary of reference completeness | TaxaLikely, TaxaAssign |
| `in_reference` | Census column: count of species in user's match_df | TaxaLikely |
| `has_seqs_not_in_ref` | Census column: species with barcodes but absent from reference | TaxaLikely |
| `is_complete` | Census column: genus fully sampled (no gaps) | TaxaLikely |
| `n_sims` | Number of Monte Carlo iterations | TaxaLikely, TaxaAssign |
| `ratio_threshold` | Minimum likelihood ratio to retain hypothesis (default 0.01) | TaxaLikely |
| `composite_id` | Unique sequence identifier (accession, version stripped) | TaxaLikely |
| `filter_top_hypotheses` | Retain only finest-rank specific candidates per query | TaxaLikely |

### Occurrence & Habitat (TaxaFetch, TaxaHabitat)

| Term | Definition | Primary package(s) |
|---|---|---|
| `occurrence` | Single documented observation of a species at a location/time | TaxaFetch |
| `point_id` | Unique identifier for exact lat/lon coordinate | TaxaFetch (origin), TaxaHabitat, TaxaExpect |
| `grid_id` | Aggregated spatial cell identifier (encodes location only) | TaxaExpect (origin), TaxaAssign |
| `main_habitat` | Winning habitat label per site (argmax of weights) | TaxaHabitat (origin), TaxaExpect, TaxaAssign, TaxaFetch |
| `habitat_scheme` | Data frame defining habitat classification (custom, IUCN, or 3-category) | TaxaHabitat |
| `habitat_weight` | Numeric 0-1 weight per habitat column per species | TaxaHabitat |
| `habitat_affinity` | Numeric per-species habitat weights (TaxaHabitat context) | TaxaHabitat |
| `habitat_fit` | LLM categorical: "expected"/"occasional"/"unlikely" (TaxaAssign context) | TaxaAssign |
| `l1_name` / `l2_name` | Level 1/Level 2 habitat category names in hierarchical scheme | TaxaHabitat |
| `l2_code` | Short code for L2 habitat category (e.g., "9.1" for IUCN) | TaxaHabitat |
| `realm` | Ecological realm: marine / freshwater / terrestrial | TaxaHabitat |
| `ecoregion_best_guess` | LLM-provided ecoregion when `geographic_context` supplied | TaxaHabitat, TaxaAssign |
| `consensus_habitat` | Assemblage-level habitat from per-species weight aggregation | TaxaHabitat |
| `spatial_flag` | Plausibility flag: "likely" / "questionable" / "unlikely" | TaxaHabitat |
| `physical_zone` | Derived: inland / coastal / marine_shallow / marine_deep / marine_abyssal | TaxaHabitat |
| `geo_match` / `taxon_match` | LLM screening: does dataset overlap query area / contain target taxon? | TaxaFetch |
| `bio_score` | Keyword-match count estimating dataset's biological relevance | TaxaFetch |
| `source` / `source_type` | Data provenance flag (GBIF, DataONE, Supplemental, BioTime) | TaxaFetch |

### Prior Estimation (TaxaExpect)

| Term | Definition | Primary package(s) |
|---|---|---|
| `theta` | Probability that a sampled individual belongs to species X at a site | TaxaExpect |
| `prior_mean` / `prior_alpha` / `prior_beta` | Beta-distributed prior parameters | TaxaExpect (output), TaxaAssign (input) |
| `phi` | Beta precision = alpha + beta (effective sample size) | TaxaExpect, TaxaAssign |
| `Tier 1` | Common species (>= min_obs_threshold detections); full GLMM | TaxaExpect |
| `Tier 2` | Rare detected species (< threshold); intercept-only model | TaxaExpect |
| `Tier 3` | Undetected species; proxy priors from singletons/global floor | TaxaExpect |
| `singleton` | (TaxaExpect) Species observed exactly once across all samples | TaxaExpect |
| `undetected_diversity` | Tier 3 proxy species (singleton_mirror or global_floor) | TaxaExpect |
| `undetected_type` | Flag: "singleton_mirror" or "global_floor" | TaxaExpect, TaxaAssign |
| `dark_diversity` | Fallback prior for species without occurrence prediction | TaxaAssign |
| `singleton_mirror` | Tier 3 proxy inheriting singleton's theta | TaxaExpect |
| `global_floor` | Tier 3 proxy: Beta(1, N_total-1) baseline | TaxaExpect |
| `observed_in_habitat` | Flag: was this species-habitat combo seen in training data? | TaxaExpect |
| `effort_threshold` | Minimum community count for cell to enter likelihood | TaxaExpect |
| `biofreq_model` | S3 class for fitted TaxaExpect model | TaxaExpect |
| `scale_params` | Stored covariate scaling (center, scale) for prediction | TaxaExpect |
| `Moran` / `MEM` | Moran's Eigenvector Maps for spatial autocorrelation | TaxaExpect |

### Posterior & Consensus (TaxaAssign)

| Term | Definition | Primary package(s) |
|---|---|---|
| `posterior` / `posterior_point_est` / `posterior_mean` / `posterior_sd` | Bayesian posterior probability (likelihood x prior, normalized) | TaxaAssign |
| `confidence_score` | Fraction of MC simulations in which hypothesis had highest posterior | TaxaAssign |
| `compute_posterior` | Core function: Bayesian update with optional MC | TaxaAssign |
| `posterior_consensus` | Derive single consensus taxon per sample via LCA on plausible set | TaxaAssign |
| `score_consensus` | Score-based consensus (no Bayesian model): min_score + max_gap + rank_thresholds | TaxaAssign |
| `consensus_taxon` / `consensus_rank` | Output: consensus name and rank | TaxaAssign |
| `is_resolved` | Logical: consensus at finest rank in rank_system | TaxaAssign |
| `LCA` | Least Common Ancestor: finest rank at which all plausible hypotheses agree | TaxaAssign |
| `cumulative_threshold` | Fraction of posterior mass for plausible set (default 0.9) | TaxaAssign |
| `plausible` / `plausible_taxa` | Top hypotheses summing to cumulative_threshold of posterior | TaxaAssign |
| `downranking` | Narrowing coarse consensus when reference has exactly one finer taxon | TaxaAssign |
| `species_reference` | Reference for downranking (unreferenced_species_result or data.frame) | TaxaAssign |
| `assign_taxa_llm` | LLM-shortcut pipeline: score-weighted likelihoods + LLM priors | TaxaAssign |
| `range_status` | LLM output: biogeographic status (native, introduced, etc.) | TaxaAssign |
| `habitat_fit` | LLM output: expected / occasional / unlikely | TaxaAssign |
| `information_quality` | LLM self-assessment: high / moderate / low data availability | TaxaAssign |
| `prior_phi` | Beta concentration mapped from information_quality | TaxaAssign |
| `score_sharpness` | Controls how score differences map to likelihood differences | TaxaAssign |
| `unknown_lik_weight` | Likelihood fraction reserved for unknown_species hypothesis | TaxaAssign |
| `known_present` / `known_absent` | Species confirmed present/absent at site (LLM context + prior suppression) | TaxaAssign |
| `update_prior_from_consensus` | Empirical Bayes: boost priors for confirmed species in unresolved samples | TaxaAssign |
| `presence_multiplier` | Prior boost factor for confirmed species (default 5) | TaxaAssign |
| `join_priors` | Map sample_ids to grid locations; merge likelihoods + TaxaExpect priors | TaxaAssign |
| `taxaexpect_priors` | TaxaExpect output: prior probabilities per taxon x site x habitat | TaxaAssign |
| `report_params` | Attribute on output data frames recording key parameters | TaxaAssign |
| `generate_report` | Publication-ready Methods + Results text | TaxaAssign |

### LLM & Text Generation (TaxaTools, cross-package)

| Term | Definition | Primary package(s) |
|---|---|---|
| `llm_fn` | Pluggable LLM provider function: `function(prompt_str, ...) -> character(1)` | TaxaTools (defined), all packages |
| `call_anthropic_api` | Anthropic Claude provider | TaxaTools |
| `call_gemini_api` | Google Gemini provider | TaxaTools |
| `call_openai_api` | OpenAI ChatGPT provider | TaxaTools |
| `call_ollama_api` | Local Ollama provider | TaxaTools |
| `prompt_api` | Multi-chunk llm_prompt dispatcher | TaxaTools |
| `report_context` | S3 object: verified facts for grounding LLM text generation | TaxaTools |
| `draft_methods_text` | LLM-drafted methods from R code | TaxaTools |
| `draft_results_text` | LLM-drafted results from R objects | TaxaTools |
| `habitat_prompt` | S3 object for habitat assignment LLM prompts | TaxaHabitat |

---

## Section 4: Summary of Recommended Actions for Prompt 9

### Must Fix (inconsistency causes confusion)

1. **Standardize rank vector parameter name to `rank_system`** across TaxaTools
   (`taxonomy_ranks`), TaxaMatch (`rank_order`), TaxaLikely, and TaxaAssign. Alias old
   names with deprecation warnings.

2. **Rename `taxonomy_code_a`** in TaxaLikely to something descriptive (e.g.,
   `finest_rank_col` or `species_col`). Internal only, no user impact.

3. **Rename `traitor_threshold`** in TaxaLikely to `mislabel_threshold` (or
   `mislabel_margin`). The term "traitor" is opaque and carries unintended connotation.

4. **Fix "Ghost prior values" heading** in `TaxaAssign/inst/PRIOR_LIKELIHOOD_MATCHING.md`
   (flagged Session 40, still not renamed).

5. **Disambiguate `singleton`**: Add qualifier in TaxaExpect ("singleton species" or
   "single-detection species") to distinguish from TaxaLikely's "singleton sequence".
   Consider renaming TaxaExpect's concept in variable names.

### Should Fix (poor discoverability)

6. **Add `@details` sections** with plain-English explanations for: H1/H2/H3,
   score_logit/gap_logit, shrinkage/prior_weight, theta, dark_diversity,
   cumulative_threshold, score_sharpness, information_quality.

7. **Add ecosystem glossary** — either as a vignette in TaxaAssign or as a shared
   document. The glossary in Section 3 above is a starting point.

8. **Document the `col_map` pattern** at ecosystem level — it's the same concept in
   TaxaTools, TaxaMatch, and TaxaFetch but not cross-referenced.

9. **Document hypothesis_type values** in one canonical location (TaxaLikely roxygen for
   `evaluate_likelihoods()` and TaxaAssign roxygen for `compute_posterior()`) listing ALL
   possible values and which package generates each.

### Low Priority (cosmetic)

10. **Qualify `score`** in TaxaTools `verify_taxon_names()` roxygen to avoid confusion:
    "backbone match confidence score (0-1); unrelated to sequence match scores used
    elsewhere in the TaxaID ecosystem."

11. **Document `prompt` type distinction** — plain string (TaxaTools `draft_*`) vs S3
    object (TaxaFetch/TaxaHabitat `*_prompt`).

---

## Appendix: Term Counts by Package

| Package | Terms identified | Inconsistencies flagged |
|---|---|---|
| TaxaTools | 27 | 2 (taxonomy_ranks naming, score overload) |
| TaxaMatch | 57 | 1 (rank_order naming) |
| TaxaLikely | 110+ | 3 (singleton, taxonomy_code_a, traitor) |
| TaxaFetch | 90+ | 0 (internally consistent) |
| TaxaHabitat | 68 | 0 (internally consistent) |
| TaxaExpect | 25 | 1 (singleton meaning) |
| TaxaAssign | 96 | 1 (ghost remnant) |
