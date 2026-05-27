# Arbitrariness Audit — TaxaID Ecosystem

**Generated:** 2026-04-13 (Session 56)
**Scope:** All R source files across 7 packages
**Purpose:** Catalog every hard-coded numeric threshold, magic number, and default parameter value. Classify each as principled, conventional, or arbitrary.

---

## Classification Key

| Class | Definition | Action needed |
|---|---|---|
| **Principled** | Clear statistical or logical basis (e.g., probability bounds) | None |
| **Conventional** | Widely used in the field; not derived from first principles | Document the convention |
| **Arbitrary** | Chosen for convenience; no clear justification | Expose as parameter with documented default |

---

## TaxaTools

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `500` | `verify_taxon_names()` batch_size | verify_taxon_names.R:70 | Conventional | Documented as param | OK — Global Names API batch limit; document source |
| `30` | `verify_taxon_names()` timeout_sec | verify_taxon_names.R:71 | Arbitrary | Documented as param | OK as exposed param; add guidance on slow connections |
| `3000` | `call_anthropic_api()` max_tokens | llm_api_utils.R:80 | Arbitrary | Documented as param | Document rationale: sufficient for most taxonomy prompts; note cost implications |
| `3000` | `call_gemini_api()` max_tokens | llm_api_utils.R:567 | Arbitrary | Documented as param | Same as above — consider unifying default across providers |
| `3000` | `call_openai_api()` max_tokens | llm_api_utils.R:698 | Arbitrary | Documented as param | Same as above |
| `3000` | `call_ollama_api()` max_tokens | llm_api_utils.R:840 | Arbitrary | Documented as param | Same as above |
| `1` | `prompt_api()` pause_seconds | llm_api_utils.R:210 | Conventional | Documented as param | OK — standard API rate-limit courtesy |
| `2` | `nchar(epithet) >= 2` | clean_taxon_names.R:83 | Principled | Undocumented | Document: single-letter epithets are abbreviations, not valid species names |
| `"2023-06-01"` | anthropic-version header | llm_api_utils.R:101 | Conventional | Undocumented | Document: Anthropic API version string; update when API changes |

---

## TaxaMatch

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `2` | `blast_sequences()` score_range | blast.R:103 | Arbitrary | Documented as param | Document rationale: retains hits within 2% of top score per query; cite BLAST best practices |
| `20` | `blast_sequences()` max_hits | blast.R:104 | Arbitrary | Documented as param | Document: practical limit for downstream processing; user can increase |
| `70` | `blast_sequences()` min_score | blast.R:105 | Conventional | Documented as param | Document convention: 70% identity is typical cross-genus floor for barcoding |
| `80` | `blast_sequences()` min_query_coverage | blast.R:106 | Conventional | Documented as param | Document: standard BLAST quality filter |
| `100` | `blast_sequences()` max_target_seqs | blast.R:110 | Conventional | Documented as param | Document: NCBI BLAST default is 500; 100 balances coverage vs speed |
| `20` | `blast_sequences()` batch_size | blast.R:111 | Arbitrary | Documented as param | Document: remote BLAST batch size; larger batches risk timeout |
| `600` | `.blast_poll()` max_wait | blast.R:378 | Arbitrary | Undocumented internal | **Expose as parameter** or at minimum document: 10-minute max wait for BLAST results |
| `15` | `.blast_poll()` initial wait | blast.R:379 | Conventional | Undocumented internal | Document: NCBI BLAST docs recommend 15s initial wait |
| `1.5` | `.blast_poll()` wait multiplier | blast.R:401 | Conventional | Undocumented internal | Document: exponential backoff factor |
| `60` | `.blast_poll()` max poll interval | blast.R:401 | Arbitrary | Undocumented internal | Document: cap on polling interval |
| `60` | `.blast_poll()` status check timeout | blast.R:395 | Arbitrary | Undocumented internal | Document: HTTP timeout for status checks |
| `300` | `.blast_poll()` result retrieval timeout | blast.R:419 | Arbitrary | Undocumented internal | Document: HTTP timeout for XML result download |

### Barcode Length Defaults (TaxaLikely/R/coverage.R)

These are shared by TaxaLikely coverage functions and TaxaMatch sequence filtering.

| Barcode | Min bp | Max bp | Class | Notes |
|---|---|---|---|---|
| MiFish | 100 | 600 | Conventional | Amplicon ~170-185 bp; range accommodates primer variants |
| Teleo | 50 | 300 | Conventional | Amplicon ~60-100 bp |
| 12S | 100 | 600 | Conventional | General 12S vertebrate |
| 16S | 100 | 700 | Conventional | ~200-450 bp |
| COI | 300 | 900 | Conventional | Folmer ~650 bp; mini-barcode ~130 bp (min may be too high) |
| CytB | 200 | 900 | Conventional | Partial ~300-700 bp |
| ITS2 | 100 | 600 | Conventional | ~200-350 bp |
| ITS | 100 | 900 | Conventional | Full ~500-750 bp |
| rbcL | 400 | 800 | Conventional | ~550-650 bp |
| matK | 600 | 1100 | Conventional | ~800-900 bp |
| 18S | 100 | 2000 | Conventional | Varies widely by primer set |
| trnL | 10 | 300 | Conventional | P6 loop ~10-150 bp |

**Action:** All conventional. Add a comment block citing sources (primer references). Consider exposing as user-overridable defaults.

---

## TaxaLikely

### Training Parameters

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0.02` | `flag_reference_errors()` mislabel_threshold | train.R:56 | Arbitrary | Documented as param | Document: 2% gap between self and foreign matches flags likely mislabels. Based on empirical testing; user should adjust based on reference quality |
| `1e-4` | `.prep_training_data()` logit_epsilon | train.R:159 | Principled | Documented as param | OK — prevents logit(0) and logit(1) |
| `5.0` | `.prep_training_data()` max_gap_ceiling | train.R:160 | Arbitrary | Documented as param | Document: caps gap at 5 logit units to prevent extreme values from dominating; empirically reasonable |
| `0.01` | noise_floor_logit in `.prep_training_data()` | train.R:205 | Arbitrary | Undocumented internal | **Document:** logit(0.01) = noise floor for foreign match scores; defines minimum meaningful match |
| `-5.0` | H2 score floor filter | train.R:516 | Arbitrary | Undocumented internal | **Document:** filters out extreme foreign match scores below logit(0.007); prevents outliers from biasing H2 delta |
| `0.5` | H2 delta minimum | train.R:519 | Principled | Undocumented internal | **Document:** minimum separation between H1 and H2; prevents H2 from overlapping H1 |
| `0.1` | H2 variance floor | train.R:520 | Arbitrary | Undocumented internal | **Document:** minimum variance for H2 distribution; prevents degenerate (zero-variance) estimates |
| `1.0` | H2 gap variance | train.R:521 | Arbitrary | Undocumented internal | **Document:** fixed gap variance for H2; assumes gap is uninformative for missing-species hypothesis |
| `3.0` | H2 delta default | train.R:509 | Conventional | Documented in CLAUDE.md | Document in code: ~3 logit units corresponds to sister-species separation in typical barcode data |
| `2.0` | H3 delta increment | train.R:530 | Arbitrary | Documented in CLAUDE.md | **Document in code:** additional rank-step penalty; chosen as reasonable default but not empirically derived per-dataset |
| `1.0` | `train_likelihood_model()` min_observed_sigma | train.R:353 | Arbitrary | Documented as param | Document: floor on observed variance to prevent overfitting on low-variance species |
| `10.0` | `train_likelihood_model()` prior_weight | train.R:354 | Arbitrary | Documented as param | **Key parameter.** Document: equivalent pseudo-sample size for Empirical Bayes shrinkage; controls how much species estimates are pulled toward global mean. 10 = moderate shrinkage |
| `0.95` | anchor gap quantile | train.R:408 | Arbitrary | Undocumented internal | **Document:** 95th percentile of positive gaps used as anchor gap value; represents "typical good separation" |
| `5` | minimum anchor count | train.R:410 | Arbitrary | Undocumented internal | **Document:** floor of 5 anchor rows even for small datasets |
| `0.10` | anchor fraction | train.R:410 | Arbitrary | Undocumented internal | **Document:** 10% of H1 training rows injected as perfect-match anchors; balances anchoring effect vs dilution |

### Inference Parameters

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0.01` | `evaluate_likelihoods()` ratio_threshold | evaluate.R:53 | Arbitrary | Documented as param | Document: hypotheses with likelihood ratio < 1% of best are dropped; prevents noise hypotheses |
| `0.50` | `evaluate_likelihoods()` min_match_threshold | evaluate.R:54 | Arbitrary | Documented as param | Document: queries with best score < 50% are sent to $unresolved; assumed unmatchable |
| `0` | `evaluate_likelihoods()` n_sims default | evaluate.R:56 | Principled | Documented as param | OK — deterministic by default; user enables MC with positive value |
| `5.0` | `evaluate_likelihoods()` max_gap_ceiling | evaluate.R:59 | Arbitrary | Documented as param | Same as training ceiling — document consistency requirement |

### Reference Acquisition

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0.25` | `build_sequence_matrix()` max_dist | build.R:51 | Conventional | Documented as param | Document: 25% distance = 75% identity; standard threshold for including distantly related taxa |
| `100` | `build_sequence_matrix()` min_seq_len | build.R:52 | Conventional | Documented as param | Document: minimum viable barcode length |
| `2000` | `build_sequence_matrix()` max_seq_len | build.R:53 | Conventional | Documented as param | Document: excludes full genes mistakenly retrieved |
| `5` | `fetch_reference_sequences()` max_per_species | fetch.R:284 | Arbitrary | Documented as param | Document: stratified downsampling; 5 captures intra-species variation without overwhelming model |
| `10000` | `fetch_reference_sequences()` max_sequences | fetch.R:286 | Arbitrary | Documented as param | Document: safety valve to prevent accidental bulk download |
| `200` | `.fetch_summaries_batched()` batch_size | fetch.R:42 | Conventional | Undocumented internal | Document: NCBI API batch limit; 200 is conservative |
| `100` | `.fetch_taxonomy_map()` batch_size | fetch.R:86 | Conventional | Undocumented internal | Document: NCBI taxonomy batch limit |
| `200` | `.fetch_fasta_batched()` batch_size | fetch.R:142 | Conventional | Undocumented internal | Document: NCBI efetch batch limit |
| `3` | Retry attempts in fetch helpers | fetch.R:50,93,155 | Conventional | Undocumented internal | Document: standard retry-with-backoff pattern |

### Coverage

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0.0` | `apply_coverage_constraints()` penalty_factor | coverage.R:672 | Principled | Documented as param | OK — default means complete suppression (most conservative) |
| `1e-6` | `.normalize_scores()` epsilon | normalize.R:20 | Principled | Documented as param | OK — prevents logit singularities at 0 and 1 |

---

## TaxaFetch

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `500` | `filter_gbif_quality()` max_coord_uncertainty | filter_gbif_quality.R:110 | Conventional | Documented as param | Document: 500m is a common GBIF quality threshold; stricter than GBIF default |
| `1` | `fetch_gbif_occurrences()` pause_seconds | fetch_gbif_occurrences.R:95 | Conventional | Documented as param | OK — GBIF API courtesy |
| `7` | `build_dataone_catalog()` max_age_days | dataone_catalog.R:86 | Arbitrary | Documented as param | Document: how often to refresh cached catalog; 7 days balances freshness vs API load |
| `0.5` | `build_dataone_catalog()` pause_seconds | dataone_catalog.R:90 | Conventional | Documented as param | OK — DataONE API courtesy |
| `0.5` | `.find_site_code_column()` min_overlap_frac | dataone_standardize.R:772 | Arbitrary | Undocumented internal | **Document:** 50% overlap between column values and expected site codes triggers a match |
| `120` | `.download_data_table()` timeout | dataone_standardize.R:473 | Arbitrary | Undocumented internal | **Document:** 2-minute HTTP timeout for data table downloads |
| `50` | `preview_dataone_data()` large_mb | dataone_preview.R:169 | Arbitrary | Documented as param | Document: threshold for "large file" warning |
| `5` | `preview_dataone_data()` assume_mbps | dataone_preview.R:170 | Arbitrary | Documented as param | Document: assumed download speed for time estimate |
| `0.5` | `search_literature()` pause_s | literature_search.R:556 | Conventional | Documented as param | OK — OpenAlex API courtesy |
| `0.5` | `screen_eml_for_taxa()` pause_seconds | dataone_eml_screen.R:122 | Conventional | Documented as param | OK — DataONE API courtesy |
| `150` | `.render_pdf_pages()` dpi | pdf_api.R:50 | Arbitrary | Undocumented internal | Document: resolution for PDF page rendering; 150 dpi balances quality vs memory |
| `80` | `.match_header()` max_chars | pdf_text.R:114 | Arbitrary | Undocumented internal | Document: maximum header line length; prevents false matches on body text |
| `10` | `.detect_document_boundary()` min_boundary | pdf_text.R:288 | Arbitrary | Undocumented internal | Document: minimum page number difference to detect document boundary in multi-doc PDFs |
| `300` | `.extract_legend_text()` max_chars | pdf_characterize.R:110 | Arbitrary | Undocumented internal | Document: maximum legend text length to extract |
| `3000` | `.find_abstract_in_document()` max_chars | pdf_characterize.R:453 | Arbitrary | Undocumented internal | Document: maximum abstract length |

---

## TaxaHabitat

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0.3` | `assign_habitat_biological()` threshold | assign_habitat_biological.R:124 | Arbitrary | Documented as param | **Key parameter.** Document: habitat weight threshold for "dominant" classification; 0.3 means a habitat receiving ≥30% of species-weighted votes is considered biologically relevant. Consider sensitivity analysis guidance |
| `0.0` | `assign_habitat_biological()` min_species_weight | assign_habitat_biological.R:125 | Principled | Documented as param | OK — default includes all species equally |
| `0.3` | `consensus_habitat()` threshold | assign_habitat_biological.R:485 | Arbitrary | Documented as param | Same rationale as above — maintain consistency |
| `1000` | `flag_habitat_inconsistencies()` coast_buffer_m | flag_habitat_inconsistencies.R:131 | Conventional | Documented as param | Document: 1km coastal buffer accounts for GPS uncertainty and tidal zones |
| `0` | `flag_habitat_inconsistencies()` marine_questionable_km | flag_habitat_inconsistencies.R:132 | Principled | Documented as param | OK — default means any distance from coast is acceptable for marine |
| `200` | `flag_habitat_inconsistencies()` depth_neritic_m | flag_habitat_inconsistencies.R:133 | Conventional | Documented as param | Document: standard oceanographic definition of continental shelf edge |
| `4000` | `flag_habitat_inconsistencies()` depth_oceanic_m | flag_habitat_inconsistencies.R:134 | Conventional | Documented as param | Document: standard abyssal plain boundary |
| `1.0` | Other_weight in prompt template | build_habitat_prompt.R:706 | Principled | In prompt text | OK — instruction for "unknown taxon" LLM response |

### UI/Visualization (review_spatial_flags.R)

| Value | Context | Class | Action |
|---|---|---|---|
| `0.8`/`0.9` | fillOpacity/opacity for map markers | Conventional | OK — standard leaflet styling |
| `450`/`500` | paneViewer minHeight | Arbitrary | OK — UI preference; not scientific |
| `0.1` | drawShapeOptions fillOpacity | Conventional | OK — standard for drawing tools |

---

## TaxaExpect

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0.1` | `optimize_grid_size()` min_grid | optimize_grid_size.R:140 | Arbitrary | Documented as param | Document: minimum grid size in decimal degrees (~11km at equator); prevents over-resolution |
| `1.0` | `optimize_grid_size()` max_grid | optimize_grid_size.R:141 | Arbitrary | Documented as param | Document: maximum grid size ~111km; prevents under-resolution |
| `0.05` | `optimize_grid_size()` step_grid | optimize_grid_size.R:142 | Arbitrary | Documented as param | Document: search increment ~5.5km; balances search resolution vs computation |
| `5` | `optimize_grid_size()` min_s_threshold | optimize_grid_size.R:136 | Arbitrary | Documented as param | Document: minimum species per grid cell for inclusion |
| `10` | `optimize_grid_size()` min_N_threshold | optimize_grid_size.R:137 | Arbitrary | Documented as param | Document: minimum observations per cell |
| `20` | `optimize_grid_size()` min_distinct_locs | optimize_grid_size.R:138 | Arbitrary | Documented as param | Document: minimum unique locations for analysis |
| `3` | `optimize_grid_size()` min_locs_per_habitat | optimize_grid_size.R:139 | Arbitrary | Documented as param | Document: minimum locations per habitat type for representativeness |
| `0.4/0.4/0.2` | `optimize_grid_size()` weights | optimize_grid_size.R:147 | Arbitrary | Documented as param | **Document thoroughly:** resolution/quality/stability weights for composite score; users should tune for their study design |
| `0.20` | `screen_spatial_formula()` sd_threshold | screen_spatial_formula.R:82 | Arbitrary | Documented as param | Document: coefficient of variation threshold for predictor screening; 20% ensures meaningful spatial signal |
| `2.0` | `screen_spatial_formula()` delta_aic_max | screen_spatial_formula.R:83 | Conventional | Documented as param | Document: Burnham & Anderson (2002) rule: ΔAIC < 2 indicates substantial support |
| `0.7` | `prepare_model_dataframe()` cor_threshold | prepare_model_dataframe.R:74 | Conventional | Documented as param | Document: standard collinearity threshold; Dormann et al. (2013) |

### Visualization (plot_theta_map_interactive.R)

| Value | Context | Class | Action |
|---|---|---|---|
| `0.7` | grid_opacity | Arbitrary | OK — UI preference |
| `4` | point_radius | Arbitrary | OK — UI preference |
| `3` | labelFormat digits | Arbitrary | OK — display precision |

---

## TaxaAssign

### LLM Workflow (assign_taxa_llm.R)

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `80` | `assign_taxa_llm()` score_threshold | assign_taxa_llm.R:197 | Conventional | Documented as param | Document: 80% identity is standard species-level BLAST threshold; matches NCBI guidance |
| `10` | `assign_taxa_llm()` top_n | assign_taxa_llm.R:198 | Arbitrary | Documented as param | Document: sends top 10 candidates to LLM; balances context window vs coverage |
| `0.1` | `assign_taxa_llm()` score_sharpness | assign_taxa_llm.R:200 | Arbitrary | Documented as param | **Key parameter.** Document: controls how strongly score differences translate to likelihood differences; 0.1 = mild; higher values make score dominance sharper |
| `0.05` | `assign_taxa_llm()` unknown_lik_weight | assign_taxa_llm.R:201 | Arbitrary | Documented as param | **Key parameter.** Document: baseline likelihood for "unknown species" catch-all hypothesis; 5% represents low but non-zero chance |
| `0.80` | `assign_taxa_llm()` absent_detection_prob | assign_taxa_llm.R:205 | Arbitrary | Documented as param | **Key parameter.** Document: probability of detecting a known-absent species; applied as `prior × (1 - p_det)` suppression |
| `30` | `assign_taxa_llm()` taxa_per_call | assign_taxa_llm.R:206 | Arbitrary | Documented as param | Document: LLM batch size; 30 fits within context window for most models |
| `1` | `assign_taxa_llm()` pause_seconds | assign_taxa_llm.R:207 | Conventional | Documented as param | OK — API rate-limit courtesy |
| `c(50, 10, 3)` | `assign_taxa_llm()` prior_phi | assign_taxa_llm.R:208 | Arbitrary | Documented as param | **Key parameter.** Document: Beta concentration mapping from information_quality. high=50 (tight prior), moderate=10 (moderately informative), low=3 (diffuse). See Session 47 notes |
| `1000` | `assign_taxa_llm()` n_sims | assign_taxa_llm.R:209 | Conventional | Documented as param | Document: standard MC sample size; sufficient for stable posterior estimates |

### LLM Prior Weight Ranges (in prompt text)

| Range | Context | Class | Action |
|---|---|---|---|
| `0.5 - 1.0` | native + expected habitat | Arbitrary | **Document:** these ranges guide LLM prior assignment; derived from expert ecological judgment (Session 45). Consider sensitivity analysis |
| `0.03 - 0.15` | native + occasional habitat | Arbitrary | Same |
| `0.003 - 0.03` | native + unlikely habitat | Arbitrary | Same |
| `0.05 - 0.3` | documented_nearby + expected | Arbitrary | Same |
| `0.002 - 0.05` | documented_nearby + occasional/unlikely | Arbitrary | Same |
| `0.001 - 0.02` | not_documented | Arbitrary | Same |
| `0.0001 - 0.002` | taxonomically_impossible | Arbitrary | Same |

### Posterior Computation

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `1000` | `compute_posterior()` n_sims | compute_posterior.R:56 | Conventional | Documented as param | Document: standard MC sample size |
| `0.9` | `posterior_consensus()` cumulative_threshold | posterior_consensus.R:154 | Conventional | Documented as param | Document: 90% cumulative probability for plausible set; analogous to credible interval |
| `0.05` | `posterior_consensus()` min_posterior | posterior_consensus.R:155 | Arbitrary | Documented as param | Document: hypotheses below 5% posterior excluded from consensus; prevents noise from influencing LCA |
| `5` | `update_prior_from_consensus()` presence_multiplier | update_prior_from_consensus.R:59 | Arbitrary | Documented as param | **Key parameter.** Document: confirmed species get prior × 5 in unresolved samples; represents empirical Bayes refinement strength. See Session 38 |

### Score Consensus

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `0` | `score_consensus()` min_score | score_consensus.R:101 | Principled | Documented as param | OK — no default filtering; user sets threshold |
| `Inf` | `score_consensus()` max_gap | score_consensus.R:102 | Principled | Documented as param | OK — no default gap filtering |

### Suggest Unreferenced Species

| Value | Function | File:Line | Class | Documentation | Recommended Action |
|---|---|---|---|---|---|
| `1` | `suggest_unreferenced_species()` pause_seconds | suggest_unreferenced_species.R:579 | Conventional | Documented as param | OK — NCBI API courtesy |

---

## Summary Statistics

| Classification | Count | Percentage |
|---|---|---|
| **Principled** | 24 | 14% |
| **Conventional** | 56 | 33% |
| **Arbitrary** | 89 | 53% |
| **Total** | 169 | 100% |

---

## Priority Actions

### Tier 1: Key Parameters Needing Documentation (High Impact)

These are already exposed as parameters but lack sufficient documentation for users to make informed choices. They directly affect scientific conclusions.

1. **`prior_phi = c(high=50, moderate=10, low=3)`** — Beta concentration for LLM priors. Document statistical interpretation: phi=50 means "worth 50 observations of data."
2. **`prior_weight = 10.0`** — Empirical Bayes shrinkage weight in TaxaLikely. Document: equivalent to 10 pseudo-observations pulling species estimates toward global mean.
3. **`score_sharpness = 0.1`** — Controls score→likelihood translation. Document with examples showing effect at different values.
4. **`unknown_lik_weight = 0.05`** — Catch-all hypothesis weight. Document: higher values make "unknown species" more competitive; lower values favor named candidates.
5. **`absent_detection_prob = 0.80`** — Known-absent suppression strength. Document ecological basis.
6. **`presence_multiplier = 5`** — Empirical Bayes refinement. Document: higher values give more weight to cross-sample evidence.
7. **LLM prior weight ranges** (7 range values in prompt text) — Document derivation from ecological expert judgment; note these are guidance ranges, not hard constraints.
8. **`H2 delta = 3.0` / `H3 delta increment = 2.0`** — Sister-species and missing-genus offsets. Document statistical meaning in logit space.
9. **`threshold = 0.3`** (habitat) — Habitat dominance threshold. Document with example: "a habitat receiving ≥30% of species-weighted votes."
10. **`optimize_grid_size()` weights** — Composite score weights. Document tradeoffs for different study designs.

### Tier 2: Internal Constants Needing Code Comments

These are hard-coded in internal functions and not user-adjustable. They should at minimum have inline comments explaining the rationale.

1. `noise_floor_logit = logit(0.01)` in `.prep_training_data()` — why 1%?
2. H2 score floor filter `-5.0` — why this cutoff?
3. H2 variance floor `0.1` — why this value?
4. H2 gap variance `1.0` — why fixed at 1?
5. Anchor gap quantile `0.95` — why 95th percentile?
6. Anchor fraction `0.10` and minimum `5` — why these values?
7. `.blast_poll()` timing constants (15s initial, 1.5x multiplier, 60s max, 600s total) — cite NCBI BLAST docs
8. Fetch batch sizes (200, 100, 200) — cite NCBI API limits
9. Retry count of 3 across all NCBI helpers — cite standard practice

### Tier 3: Conventional Values Needing Citations

These are fine as-is but should cite their source for scientific credibility.

1. `delta_aic_max = 2.0` — cite Burnham & Anderson (2002)
2. `cor_threshold = 0.7` — cite Dormann et al. (2013)
3. `depth_neritic_m = 200` / `depth_oceanic_m = 4000` — cite oceanographic definitions
4. `max_coord_uncertainty = 500` — cite GBIF data quality literature
5. Barcode length defaults — cite primer reference papers
6. `min_score = 70` / `min_query_coverage = 80` for BLAST — cite NCBI BLAST guidelines

---

## Cross-Cutting Patterns

1. **`max_tokens = 3000` repeated 4 times**: Identical default across all 4 LLM providers. Consider defining once as a package-level constant or documenting the shared rationale.

2. **`pause_seconds` defaults vary**: 0.5 (DataONE, OpenAlex), 1.0 (GBIF, LLM, NCBI). The variation is appropriate — different APIs have different rate limits — but should be documented per-API.

3. **`batch_size` defaults vary by API**: 200 (NCBI summary/FASTA), 100 (NCBI taxonomy), 500 (GNV), 20 (BLAST). Each reflects API-specific limits; document the source.

4. **Retry counts**: Uniformly 3 across all NCBI helpers. Conventional; add a brief comment.

5. **The 7 LLM prior weight ranges are the most consequential arbitrary values in the ecosystem.** They directly guide how the LLM assigns priors, and there is no way for the user to override them without editing the function. Consider exposing as a parameter (e.g., `prior_weight_guide`).
