# CLAUDE.md — TaxaID Ecosystem
# Ecosystem-level context for Claude Code. Auto-loaded from any package subdirectory.
# Package-specific context lives in each package's own CLAUDE.md.
# Last updated: 2026-05-20 (Session 80 — GitHub repo setup, CI)

---

## ⚙️ Claude Code Behavior
- After completing any task, play a completion sound: `afplay /System/Library/Sounds/Glass.aiff`
- Always ask before making changes to multiple *existing* files at once, or before any deletions
- Run `devtools::check()` after any substantive edits to a package

---

## ⚠️ Reminder for Claude
**At the start of any session involving function changes, new functions, or name changes:
remind the user to update CLAUDE.md — especially the Function Inventory and
Name Change Log — before ending the session.**

---

## ⚠️ File Loss Incident — 6 March 2026
Several TaxaExpect source files were lost during a USGS Git repository migration on
6 March 2026. Affected files were subsequently recreated from scratch. If any function
behaviour seems inconsistent with documentation, the recreated version is authoritative.
Functions confirmed recreated after the incident: `make_bbox_wkt`, `get_keys_from_context`,
`fetch_gbif_occurrences`, `create_sites_from_grid`, `optimize_grid_size`,
`filter_gbif_quality`, `assign_habitat_biological`.

---

## Developer Environment

| Item | Value |
|---|---|
| OS | macOS |
| R version | R version 4.5.2 (2025-10-31) |
| Primary IDE | RStudio |
| Git remotes | `origin` → https://github.com/kdlafferty/TaxaID (public monorepo, Session 80) |
| R library | `/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library` — set via `~/.Rprofile` `.libPaths()` call |
| ANTHROPIC_API_KEY | Set in `~/.Renviron` |
| GEMINI_API_KEY | Set in `~/.Renviron` — free tier; get key at aistudio.google.com/apikey |
| OPENAI_API_KEY | Set in `~/.Renviron` — paid account required |
| OPENALEX_API_KEY | Set in `~/.Renviron` — required since February 2026; free at openalex.org/settings/api |

---

## The TaxaID Ecosystem

| Package | Purpose | Status |
|---|---|---|
| TaxaTools | Name verification, cleaning, parsing, rank lookup, column standardisation; **LLM provider functions** (call_anthropic_api etc.); **LLM text generation** (draft_methods_text, draft_results_text); **GBIF backbone census** (census_genus_species) | In development |
| TaxaFetch | Occurrence data acquisition (GBIF, DataONE, PDF, literature search), source combination | In development |
| TaxaHabitat | Habitat assignment via LLM, spatial QAQC; depends on TaxaTools for LLM calls | New (Session 28) |
| TaxaMatch | Sequence input (DADA2/FASTA), BLAST search, match standardization | In development |
| TaxaLikely | Convert match scores to likelihoods using hierarchical Bayesian model; reference QC | New (Session 30) |
| TaxaExpect | Use occurrence and habitat data to estimate a theta prior for a taxon at a particular location | In development |
| TaxaAssign | Calculate posterior probability for a taxonomic assignment given a likelihood and a prior | Planned |
| TaxaFlag | Flag anomalous detections: contamination (lab/field blanks), allochthonous transport, taxonomic scope, handler artifacts | New (Session 60) |
| TaxaWizard | Conversational workflow designer: LLM-powered interview → .R script, .md methods, or Shiny app | New (Session 68) |

**Ecosystem logic:** TaxaTools cleans names → TaxaFetch fetches occurrence data → TaxaHabitat assigns habitats → TaxaMatch standardizes match data → TaxaLikely converts scores to likelihoods → TaxaExpect builds priors → TaxaAssign computes posteriors → TaxaFlag flags anomalous detections. TaxaWizard sits outside the dependency chain (generates scripts that call the other packages).

**Dependency chain:** TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign → TaxaFlag
TaxaMatch → TaxaLikely → TaxaAssign → TaxaFlag
TaxaWizard: no TaxaID dependencies (uses metadata JSON files as interface)

**Package split notes:**
- Session 19: TaxaFetch split out of TaxaExpect (owns data acquisition)
- Session 28: TaxaHabitat split out of TaxaFetch (owns habitat assignment + spatial QAQC); LLM provider functions moved to TaxaTools
- Session 30: TaxaMatch scope revised to thin shell; TaxaLikely created to own score→likelihood conversion
- Session 60: TaxaFlag created for post-assignment anomalous detection flagging
- Session 68: TaxaWizard created for conversational workflow design (outside dependency chain)

**Licensing:** All packages use MIT except TaxaExpect (GPL >= 3, required by glmmTMB dependency). Since TaxaExpect is only in Suggests (never Imports) for downstream packages, this does not propagate the GPL obligation to other TaxaID packages.

---

## Shared Data Interface

- Classification paths: pipe `|` delimited
- Rank labels: pipe `|` delimited, aligned positionally with classification path
- Spatial terminology (strict):
  - `point_id` = exact lat/lon coordinate identifier (created before gridding)
  - `grid_id` = aggregated spatial cell identifier (encodes location ONLY — never habitat)
- Likelihood / prior / posterior object structure: TBD — see TaxaAssign CLAUDE.md

---

## Taxonomic Backbone ID Reference

| ID | Backbone |
|---|---|
| 1 | Catalogue of Life |
| 3 | ITIS |
| 4 | NCBI |
| 9 | WoRMS |
| 11 | GBIF |

Full list: https://verifier.globalnames.org/

---

## Developer Workflow Reminder (macOS / RStudio)

```r
devtools::document()   # ALWAYS: regenerates NAMESPACE and .Rd files
devtools::test()       # run tests within the package project (uses load_all)
devtools::install()    # required before using library(Package) from another project
```

**When to run what:**

| Situation | Command | Speed |
|---|---|---|
| Editing code, running `devtools::test()` inside the package | Nothing extra — `load_all()` is implicit | Fast |
| Changed roxygen docs or added/removed exports | `devtools::document()` | Fast |
| Need to use the package from another project (`library(Package)`) | `devtools::install()` | Slow |
| Stale namespace / unexplained errors after switching branches | Restart R, then `library(Package)` | Medium |

**Rule:** `document()` alone for in-package editing/testing; add `install()` when
switching to another project that calls the package.

---

## Coding Conventions

- Native pipe `|>` throughout — never `%>%`
- `utils::globalVariables()` must be **first line** of every R file that uses NSE column names; omit entirely from files with no NSE references
- No blank lines inside `@param` roxygen blocks
- Helper/internal functions: `.` prefix + `@noRd`
- `package::function()` style for cross-package calls
- `%||%` defined ONCE in TaxaFetch `llm_api_utils.R` — never redefine elsewhere
- **`llm_fn` pattern**: LLM-calling functions accept `llm_fn = call_anthropic_api` param; users pass compatible wrapper for other providers

---

## ⚠️ Known R Footguns

### Split-string sprintf bug (recurring)
`sprintf()` does NOT concatenate multiple string arguments.
```r
# WRONG — crashes with "invalid format '%d'"
warning(sprintf("Message with %d items: ", "extra string", count))
# CORRECT
warning(sprintf("Message with %d items: extra string", count))
```
Check all `sprintf`/`warning`/`message`/`stop` calls before delivering any file.

### Roxygen blank lines inside @param
Blank line inside `@param` block → `devtools::document()` fails silently.

### read.csv numeric coercion of IUCN codes
`read.csv` parses `"9.2"` as `<double>`. Always `as.character()` before joining
against `.iucn_habitat_lookup$l2_code`.

### Logical parameter NA validation
`is.logical(NA)` returns `TRUE`. Always add `|| is.na(x)`:
```r
if (!is.logical(strict) || length(strict) != 1L || is.na(strict)) stop(...)
```

### \tabular in roxygen blocks
Use `\itemize` or `\describe` instead. If `devtools::document()` runs but does not
print "Writing <function>.Rd", a broken `\tabular` block is the first thing to check.

### taxon_match / geo_match column collision (Session 25)
`search_literature()` pre-initialises `geo_match = NA` and `taxon_match = NA`.
If screening fails partway and leaves stale values, a subsequent `left_join` creates
`.x`/`.y` duplicates. Always drop stale screening columns before rebuilding the prompt.

### prompt_api() breaking change (Session 26)
Renamed from `prompt_anthropic_api` to `prompt_api`. Params `model`, `max_tokens`,
`api_key` removed — now handled via closure passed to `llm_fn`. See TaxaFetch CLAUDE.md.

### PCRE `sub()` does not match newlines without `(?s)` (Session 33)
`sub(".*?(\\[[\\s\\S]*\\]).*", "\\1", x, perl=TRUE)` silently returns `x` unchanged
when `x` contains newlines, because `.*` in PCRE does not match `\n` by default.
Fix: add `(?s)` inline flag: `sub("(?s).*?(\\[...]\\]).*", "\\1", x, perl=TRUE)`.
This affected `assign_taxa_llm()` in TaxaAssign — LLM responses wrapped in markdown
fences were never parsed, causing all-NA `range_status` and uniform priors.

---

## Name Change Log

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
| 2026-03-28 | *(Session 33 — new)* | `audit_barcode_coverage()` | TaxaLikely | function | Barcode-aware unreferenced species detection via NCBI nucleotide; replaces `audit_reference_coverage()` for eDNA. Params: `barcode_term` (vector), `max_date`, `min_len`, `max_len` |
| 2026-03-28 | *(Session 33 — planned → Session 40 — implemented)* | `expand_unreferenced_hypotheses()` | TaxaAssign | function | Expand generic H2/H3 rows from `evaluate_likelihoods()` into named unreferenced species; convergence point for TaxaLikely likelihoods + TaxaExpect priors. Moved to TaxaAssign (not TaxaLikely) — mirrors `assign_taxa_llm()` role in LLM workflow. |
| 2026-03-28 | *(Session 33 — fix)* | `assign_taxa_llm()` JSON parse regex | TaxaAssign | bug fix | Added `(?s)` PCRE flag so `sub()` matches newlines; fixed range_status all-NA |
| 2026-03-29 | *(Session 34 — redesign)* | `audit_barcode_coverage()` | TaxaLikely | function | Corrected unreferenced definition: unreferenced = NO barcode sequence (count=0), not merely absent from user reference. Census redesigned: `in_reference`/`has_seqs_not_in_ref`/`unreferenced`/`is_complete`. NCBI API reliability: taxonomy-first species list + `retmax=0` per-species count queries + `[PDAT]` date in term string + exponential backoff. `species_list` param added. Deprecation note added (will be superseded by LLM-first `suggest_unreferenced_species()`). |
| 2026-03-29 | *(Session 34 — planned)* | `suggest_unreferenced_species()` | TaxaLikely or TaxaAssign | function | **PLANNED.** LLM-first unreferenced species detection: LLM generates plausible species per genus → remove matched species → NCBI barcode-count only on plausible remainder. Dramatically reduces API calls vs current exhaustive approach. |
| 2026-03-29 | *(Session 35 — implemented)* | `suggest_unreferenced_species()` | TaxaAssign | function | Implemented in TaxaAssign (not TaxaLikely). Returns `unreferenced_species_result` S3 character vector; `attr(result, "census")` and `attr(result, "plausible")` give full details. Barcode helpers copied from TaxaLikely (no internals import). Workflow Section 4 updated. |
| 2026-03-30 | *(Session 36 — new)* | `expand_to_family` param | TaxaAssign | `suggest_unreferenced_species()` | Family-level unreferenced taxon expansion when genus has no plausible species; `unreferenced_family` + `family_census` attributes on result. Family prompt now returns `range_status` per species; `.parse_family_response()` filters to plausible statuses before NCBI. |
| 2026-03-30 | *(Session 36 — new)* | `habitat_fit` field | TaxaAssign | `assign_taxa_llm()` output | LLM returns `habitat_fit` ("expected"/"occasional"/"unlikely") alongside `range_status`; prior weight scale integrates both dimensions. (Originally called `habitat_affinity`; renamed Session 37 — see below.) |
| 2026-03-30 | *(Session 36 — new)* | `known_present`, `known_absent`, `absent_detection_prob` | TaxaAssign | `assign_taxa_llm()` params | `known_present`: LLM context only. `known_absent`: LLM context + math suppression `prior × (1 - p_det)`. |
| 2026-03-30 | *(Session 36 — new)* | family-level unreferenced taxon insertion | TaxaAssign | `.score_to_likelihood()` | `unreferenced_family_map` param; inserts family-level unreferenced taxa when genus absent but family represented in candidates. |
| 2026-03-31 | *(Session 36 — planned → Session 39 — implemented)* | `filter_redundant_hypotheses()` | TaxaMatch | function | Drop higher-rank rows superseded by finer-rank rows within same lineage + sample_id. Lineage-local (not global). Default `rank_order = kpcofgs`. Workflows in `TaxaMatch` and `TaxaAssign` updated; placeholder `f_filter_redundant_higher_hypotheses()` removed from `TaxaAssign_llm_workflow.R`. |
| 2026-03-30 | *(Session 37 — rename)* | `ghost` (bool) | `hypothesis_type` (character) | TaxaAssign | `assign_taxa_llm()` output column; values: "specific_candidate" / "unreferenced_species" / "unreferenced_genus". Aligns with TaxaLikely. |
| 2026-03-30 | *(Session 37 — rename)* | `habitat_affinity` | `habitat_fit` | TaxaAssign | LLM categorical column in `assign_taxa_llm()` output. `habitat_affinity` retained in TaxaHabitat for numeric species habitat weights (different concept). |
| 2026-03-30 | *(Session 37 — rename)* | `missing_species` | `unreferenced_species` | TaxaAssign + TaxaLikely | `hypothesis_type` value: species absent from reference DB (no barcode sequence). |
| 2026-03-30 | *(Session 37 — rename)* | `missing_genus` | `unreferenced_genus` | TaxaAssign + TaxaLikely | `hypothesis_type` value: family-level unreferenced taxon or uncharacterised genus-level diversity. |
| 2026-03-30 | *(Session 37 — rename)* | `Main_Habitat` | `main_habitat` | TaxaHabitat, TaxaExpect, TaxaFetch | Site-level habitat column; snake_case consistency (145 occurrences across 20 files). |
| 2026-03-30 | *(Session 37 — rename)* | `ctx$habitat` | `ctx$main_habitat` | TaxaAssign | Recognised context field in `assign_taxa_llm()`; aligns with `main_habitat` from TaxaHabitat/TaxaExpect. |
| 2026-03-30 | *(Session 37 — planned → Session 38 — implemented)* | `consensus_taxonomy()` | TaxaAssign | function | LCA among plausible posterior hypotheses; one row per sample_id. All named `hypothesis_type` values contribute; only `unknown_species` excluded. `backbone_id` param added. `lookup_missing_taxonomy` uses `change_backbone()` to parse `verify_taxon_names()` output. Propagates `prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1`, `taxon_changed` from `update_prior_from_consensus()`. |
| 2026-03-30 | *(Session 38 — new)* | `update_prior_from_consensus()` | TaxaAssign | function | One-pass empirical Bayes refinement: confirmed species (from `is_resolved = TRUE`) get `prior_mean × presence_multiplier` in unresolved samples only; `compute_posterior()` re-run on those samples. Adds `prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1` to returned dataframe for propagation by `consensus_taxonomy()`. |
| 2026-03-30 | *(Session 38 — new)* | `inst/TaxaAssign_consensus_workflow.R` | TaxaAssign | workflow | Standalone consensus workflow starting from `result`; covers overview, resolved/ambiguous/unresolvable inspection, threshold sensitivity, winner-takes-all vs LCA comparison. |
| 2026-03-30 | *(Session 38 — added)* | `devtools` workflow guide | TaxaAssign CLAUDE.md | docs | When to run `document()` vs `install()` vs restart; added to Developer Workflow section. |
| 2026-03-31 | *(Session 39 — rename)* | `suggest_plausible_ghosts()` | `suggest_unreferenced_species()` | TaxaAssign | function | File renamed; S3 class `spg_result` → `unreferenced_species_result`; param `ghost_taxa` → `unreferenced_taxa` in `assign_taxa_llm()`; attribute `ghost_family` → `unreferenced_family`. |
| 2026-03-31 | *(Session 39 — rename)* | `$ghosts` | `$unreferenced` | TaxaLikely | `audit_barcode_coverage()` + `audit_reference_coverage()` return value | Census column also renamed: `ghosts` → `unreferenced`. |
| 2026-03-31 | *(Session 40 — new)* | `inst/TaxaAssign_bayesian_workflow.R` | TaxaAssign | workflow | End-to-end non-LLM (Bayesian) workflow: TaxaLikely likelihoods → unreferenced expansion → TaxaExpect priors → dark diversity fallback → `compute_posterior()` → `consensus_taxonomy()`. 7 sections parallel to the LLM workflow. |
| 2026-04-01 | *(Session 41 — fix)* | hardcoded `habitat` output column | `main_habitat` (respects `habitat_col` param) | TaxaExpect | `generate_full_priors()` + `generate_undetected_diversity()` | Fixed: output column was always named `habitat` regardless of `habitat_col` arg; downstream join in TaxaAssign Bayesian workflow on `main_habitat` was silently failing. Tests updated. |
| 2026-04-01 | *(Session 41 — new)* | *(new)* | `ecosystem_docs/ECOSYSTEM_WORKFLOW.md` | Ecosystem | docs | Full pipeline map: TaxaMatch → two parallel pipelines (Prior: TaxaFetch→TaxaHabitat→TaxaExpect; Likelihood: TaxaLikely) → TaxaAssign. Per-workflow inputs/outputs, save paths, two-workflow distinction. |
| 2026-04-01 | *(Session 41 — new)* | *(add saveRDS)* | workflow scripts | TaxaFetch + TaxaExpect + TaxaLikely | workflow | Added `saveRDS()` to: `Merge_sources_workflow.R` (occurrence_data), `Habitat_assign_workflow.R` (occurrences_with_habitat), `TaxaExpect_workflow.R` (model_fit + taxaexpect_priors), `TaxaLIkely_workflow.R` (real_model). |
| 2026-04-01 | *(Session 41 — new)* | *(cache-first loading)* | `TaxaAssign_bayesian_workflow.R` Sections 1–2 | TaxaAssign | workflow | Sections 1–2 now load pre-computed objects via `system.file()` paths; cache-first pattern: `real_likelihoods.rds` → `real_model.rds` + re-evaluate → error. Removes dependency on re-running TaxaLikely interactively. |
| 2026-04-01 | *(Session 42 — rename)* | `TaxaLIkely_workflow.R` | `TaxaLikely_workflow.R` | TaxaLikely | workflow file | Corrected capitalisation; all forward-facing references updated (TaxaAssign Bayesian workflow, ECOSYSTEM_WORKFLOW.md, TaxaLikely CLAUDE.md). |
| 2026-04-01 | *(Session 42 — fix)* | `threshold` param | `cumulative_threshold` | TaxaAssign | `TaxaAssign_bayesian_workflow.R` Section 8 | Wrong param name passed to `consensus_taxonomy()`; would have errored at runtime. |
| 2026-04-01 | *(Session 42 — new)* | *(Section 5 sample_meta)* | `TaxaAssign_bayesian_workflow.R` | TaxaAssign | workflow | Added 3-step sample_meta construction guide (locate/add location column → map to grid_id + main_habitat → build sample_meta with unmapped-sample warning); sections renumbered 1–8. |
| 2026-04-02 | *(Session 44 — new)* | `species_reference` param | `consensus_taxonomy()` | TaxaAssign | function | Downranking: unresolved genus/family consensus downranked when reference has exactly one finer taxon (recursive). Accepts `unreferenced_species_result` (uses `attr(x,"plausible")`) or data.frame. New `downranked` output column. Both workflow scripts updated. |
| 2026-04-03 | *(Session 46 — new)* | `geographic_context` param | `build_habitat_prompt()` | TaxaHabitat | function | Optional geographic hint; adds `GEOGRAPHIC CONTEXT:` block to prompt + requests `ecoregion_best_guess` column from LLM. Default NULL (no change to existing behavior). |
| 2026-04-03 | *(Session 46 — new)* | `consensus_habitat()` | `R/assign_habitat_biological.R` | TaxaHabitat | function | Assemblage-level consensus habitat from per-species weights; modal ecoregion extraction; `.detect_habitat_cols()` internal shared with `assign_habitat_biological()`. |
| 2026-04-03 | *(Session 46 — new)* | `build_context()` | `R/build_context.R` | TaxaAssign | function | Auto-populate `ctx` (ecoregion, main_habitat, date) from taxon names via TaxaHabitat LLM habitat prompt + synthesis call. TaxaHabitat added to Suggests. |
| 2026-04-03 | *(Session 46 — new)* | `ecoregion_best_guess` protection | `parse_hierarchical_habitat_response()` | TaxaHabitat | function | Column protected from numeric detection; included in canonical column order when present. |
| 2026-04-03 | *(Session 46 — workflow)* | LLM workflow Section 2 reordered | `TaxaAssign_llm_workflow.R` | TaxaAssign | workflow | LLM provider choice moved before context; `build_context()` shown as Option A (default), manual `ctx` as Option B. |
| 2026-04-04 | *(Session 47 — breaking)* | `prior_sd` removed from `compute_posterior()` | TaxaAssign | function | Prior uncertainty now via `prior_alpha`/`prior_beta` (Beta distribution); `rbeta()` replaces `rnorm()` for prior sampling. When columns absent, priors treated as fixed. |
| 2026-04-04 | *(Session 47 — new)* | `information_quality` field | TaxaAssign | `assign_taxa_llm()` output | LLM returns "high"/"moderate"/"low" per taxon; reflects data availability, not confidence. |
| 2026-04-04 | *(Session 47 — new)* | `prior_phi` param | TaxaAssign | `assign_taxa_llm()` | Named vector mapping `information_quality` → phi (Beta concentration). Default `c(high=50, moderate=10, low=3)`. Scalar overrides quality levels; NULL disables Beta priors. |
| 2026-04-04 | *(Session 47 — breaking)* | `n_sims` default 0 → 1000 | TaxaAssign | `assign_taxa_llm()` | MC is now informative (Beta priors provide uncertainty); default enables it. |
| 2026-04-04 | *(Session 47 — fix)* | `join_priors()` passes alpha/beta directly | TaxaAssign | function | `prior_alpha = coalesce(alpha, dark_alpha)`, `prior_beta = coalesce(beta, dark_beta)`; no longer derives `prior_sd`. |
| 2026-04-06 | *(Session 48 — new)* | `generate_report()` | TaxaAssign | function | Publication-ready Methods + Results text. Hybrid: template Methods (workflow-aware) + LLM Results (with template fallback when `llm_fn = NULL`). Params: `unreferenced_result`, `data_type`, `marker`, `context_source`, `study_description`. |
| 2026-04-06 | *(Session 48 — new)* | `report_params` attribute | TaxaAssign | interface | `compute_posterior()`, `assign_taxa_llm()`, `consensus_taxonomy()`, `update_prior_from_consensus()` now attach `attr(out, "report_params")` for `generate_report()` to read. |
| 2026-04-06 | *(Session 48 — fix)* | `report_params` misplaced in `.downrank_consensus()` | TaxaAssign | bug fix | Attribute was inside internal helper where `cumulative_threshold` etc. were not in scope; moved to end of `consensus_taxonomy()`. |
| 2026-04-06 | *(Session 48 — workflow)* | `generate_report()` added to LLM workflow | TaxaAssign | workflow | `TaxaAssign_llm_workflow.R` now calls `generate_report(result_updated, consensus_final, ...)` at end. |
| 2026-04-06 | *(Session 49 — rename)* | `consensus_taxonomy()` | `posterior_consensus()` | TaxaAssign | function | Renamed to distinguish from new `score_consensus()`. File: `R/consensus_taxonomy.R` → `R/posterior_consensus.R`. All callers updated. |
| 2026-04-06 | *(Session 49 — new)* | `score_consensus()` | TaxaAssign | function | Conventional score-based consensus: min_score + max_gap + rank_thresholds + whitelist → LCA. No model/priors needed. Default thresholds: `c(species=98, genus=95, family=90, order=85)`. |
| 2026-04-06 | *(Session 49 — workflow)* | Score consensus + comparison sections | TaxaAssign | workflow | Both `TaxaAssign_llm_workflow.R` (Sections 6–8) and `TaxaAssign_bayesian_workflow.R` (Sections 6–7) now run `score_consensus()` and compare against `posterior_consensus()`. |
| 2026-04-06 | *(Session 49 — redesign)* | `generate_report()` dual consensus support | TaxaAssign | function | Detects consensus type from columns; `result` accepts NULL for score-based; Methods/Results adapt to whichever consensus method was used. Old comparison approach removed. |
| 2026-04-06 | *(Session 49 — fix)* | `generate_report()` sprintf bug in rank_thresholds | TaxaAssign | bug fix | Split-string sprintf: format string split across args silently dropped threshold list from Methods text. |
| 2026-04-07 | *(Session 50 — new)* | `fetch_reference_sequences()` | TaxaLikely | function | Search NCBI by taxon + barcode marker → `reference_df`. Count-first estimation, resumable `cache_dir`, stratified downsampling. Based on `GetNCBIsequences3.R`. |
| 2026-04-07 | *(Session 50 — new)* | `read_reference_fasta()` | TaxaLikely | function | Read local FASTA + taxonomy table → `reference_df`. For CRUX, GenBank dumps, custom databases. |
| 2026-04-07 | *(Session 50 — new)* | `xml2` added to Imports | TaxaLikely | dependency | Required for NCBI taxonomy XML parsing in `.fetch_taxonomy_map()`. |
| 2026-04-07 | *(Session 50 — redesign)* | 5 workflow scripts replace monolithic workflow | TaxaLikely | workflow | `inst/TaxaLikely_workflow.R` superseded by `inst/workflows/1_fetch_references_workflow.R` through `5_audit_coverage_workflow.R`. |
| 2026-04-08 | *(Session 51 — new)* | `anchor_perfect` param | TaxaLikely | `train_likelihood_model()` | Pseudo-data anchoring: synthetic perfect-match rows prevent "perfection penalty". Default TRUE. `n_anchors` added to `Stats`. |
| 2026-04-08 | *(Session 51 — new)* | `inst/plot_likelihood_landscape.R` | TaxaLikely | standalone script | Two-panel H1/H2 density visualization with A/B/U points. For presentations/manuscripts, not exported. |
| 2026-04-08 | *(Session 51 — new)* | `inst/methods_background.md` | TaxaLikely | documentation | Statistical methods background (10 sections); manuscript seed adapted from early design docs. |
| 2026-04-09 | *(Session 52 — breaking)* | `clean_taxon_names()` length-preserving | TaxaTools | function | Output now same length as input; invalid names become `NA` instead of being dropped. Duplicates preserved. Callers needing old behavior: `clean_taxon_names(x) |> na.omit() |> unique()`. |
| 2026-04-09 | *(Session 52 — new)* | `inst/CITATION` files | All packages | citation | Standard R citation files for all 7 packages; each cites itself + TaxaID ecosystem. `citation("PackageName")` now works. |
| 2026-04-09 | *(Session 52 — new)* | `attr(result, "model")` on llm_fn returns | TaxaTools | interface | All 4 LLM providers (`call_anthropic_api`, `call_gemini_api`, `call_openai_api`, `call_ollama_api`) now attach `model` attribute to returned string. Non-breaking. |
| 2026-04-09 | *(Session 52 — enhancement)* | `generate_report()` citation + LLM provenance | TaxaAssign | function | Programmatic citation from `inst/CITATION`; LLM model name detected from `llm_fn` formals and included in Methods; LLM variability caveat added; unreferenced species likelihood text now workflow-aware (LLM median vs TaxaLikely H2 model). |
| 2026-04-10 | *(Session 53 — new)* | `read_sequence_table()` | TaxaMatch | function | Ingest DADA2 seqtab matrix, FASTA file, or DNAStringSet; optional taxonomy join; semicolon header parsing. |
| 2026-04-10 | *(Session 53 — new)* | `filter_sequences()` | TaxaMatch | function | Filter ASVs by length range + minimum abundance; `barcode_term` auto-detection. |
| 2026-04-10 | *(Session 53 — new)* | `blast_sequences()` | TaxaMatch | function | Remote NCBI BLAST (httr2) or local rBLAST; score window filtering (all hits within `score_range`% of top hit per query); subject length filtering; taxonomy resolution. |
| 2026-04-10 | *(Session 53 — new)* | `inst/workflow_fastq_to_match.R` | TaxaMatch | workflow | End-to-end: DADA2 output, filter, BLAST, standardize, filter redundant. |
| 2026-04-10 | *(Session 53 — new)* | `httr2`, `rentrez`, `xml2` added to Imports | TaxaMatch | dependency | Remote BLAST + taxonomy resolution. `Biostrings`, `rBLAST` added to Suggests. |
| 2026-04-11 | *(Session 54 — fix)* | BLAST URL API: Tabular → XML format | TaxaMatch | bug fix | `FORMAT_TYPE=Tabular` returned empty status page; switched to `FORMAT_TYPE=XML`. `.parse_blast_tabular()` replaced by `.parse_blast_xml()`. `.resolve_taxonomy_from_accessions()` added for accession→taxid→lineage bridge. |
| 2026-04-11 | *(Session 54 — fix)* | `.blast_poll()` sprintf + status separation | TaxaMatch | bug fix | `%d` → `%g` for non-integer elapsed time; status check separated from result retrieval (SearchInfo then XML). |
| 2026-04-12 | *(Session 55 — new)* | `build_report_context()` | TaxaTools | function | Domain-agnostic S3 `report_context` object; verified facts for grounding LLM text generation. |
| 2026-04-12 | *(Session 55 — new)* | `draft_methods_text()` | TaxaTools | function | Read R code → LLM-drafted Methods section; context-aware; statistics bleed guard; LLM caution instructions. |
| 2026-04-12 | *(Session 55 — new)* | `draft_results_text()` | TaxaTools | function | Read R objects → LLM-drafted Results section; context-aware; LLM stochasticity caveat. |
| 2026-04-12 | *(Session 55 — planned)* | `read_animl_output()` | TaxaMatch | function | **PLANNED.** Ingest Animl CSV export (camera trap images); map confidence + taxonomy to match object. |
| 2026-04-12 | *(Session 55 — planned)* | `read_birdnet_output()` | TaxaMatch | function | **PLANNED.** Ingest BirdNET CSV (acoustic detections); map confidence + species to match object. |
| 2026-04-13 | *(Session 56 — rename)* | `taxonomy_ranks` param | `rank_system` | TaxaTools | `create_taxon_names()` param | Jargon audit fix #1: harmonize with TaxaLikely/TaxaAssign. Callers in TaxaMatch `standardize_match_data()` and TaxaExpect workflow updated. |
| 2026-04-13 | *(Session 56 — rename)* | `rank_order` param | `rank_system` | TaxaMatch + TaxaAssign | `filter_redundant_hypotheses()` + `join_priors()` params | Jargon audit fix #2: harmonize across ecosystem. |
| 2026-04-13 | *(Session 56 — rename)* | `taxonomy_code_a/b/c...` internal columns | `rank_code_a/b/c...` | TaxaLikely | `.prep_training_data()` + `train_likelihood_model()` internals | Jargon audit fix #3: less cryptic internal naming. |
| 2026-04-13 | *(Session 56 — rename)* | `traitor_threshold` param | `mislabel_threshold` | TaxaLikely | `flag_reference_errors()` + `train_likelihood_model()` params | Jargon audit fix #4: self-documenting name. Workflow scripts updated. |
| 2026-04-15 | *(Session 57 — new param)* | *(new)* | `verbose` param | TaxaLikely | `evaluate_likelihoods()` | Logs species-specific param fallback to global mean when TRUE. Default FALSE. |
| 2026-04-15 | *(Session 57 — new param)* | *(new)* | `prior_weight_guide` param | TaxaAssign | `assign_taxa_llm()` | Exposes 7 hardcoded LLM prior weight ranges as user-customizable named list. Default reproduces Session 45 ranges. |
| 2026-04-15 | *(Session 57 — docs)* | Statistical defensibility comments | *(across packages)* | TaxaLikely, TaxaAssign, TaxaExpect | Code comments + @details | Efron-Morris (1973), Huson (2007), Jeffreys (1946) citations; tradeoff documentation for ad hoc decisions (H3 delta, presence_multiplier, score_sharpness, singleton_ess). |
| 2026-04-15 | *(Session 57 — new)* | `standard_ranks`, `extended_ranks`, `detect_ranks()` | TaxaTools | exported constants + function | Centralized rank definitions; downstream packages (TaxaAssign, TaxaMatch) replaced inline `std_order`/`std_tax_cols` with `TaxaTools::standard_ranks` / `TaxaTools::detect_ranks()`. |
| 2026-04-15 | *(Session 57 — new)* | `find_taxonomy_conflicts()` | TaxaTools | function | Detect higher-rank inconsistencies in taxonomy tables (e.g., same genus under different families). Adapted from GITA `f_find_taxonomic_inconsistencies()`. |
| 2026-04-15 | *(Session 57 — new)* | `consensus_reason` column | TaxaAssign | `posterior_consensus()` + `score_consensus()` output | Values: "unanimous", "single", "lca", "threshold", NA. Adapted from GITA tied-rank handling (G14). |
| 2026-04-15 | *(Session 57 — fix)* | `[GENE]` field tags in NCBI queries | TaxaLikely | `.build_search_term()` | Known barcode markers (COI, 12S, 16S, etc.) now use `[GENE]` instead of `[All Fields]`; primer names (MiFish, Teleo) fall back to `[All Fields]`. Adapted from GITA G19. |
| 2026-04-15 | *(Session 57 — new)* | `%||%` exported | TaxaTools | operator | Null-coalescing operator now exported; 5 duplicate definitions removed from TaxaFetch (2), TaxaHabitat (1), TaxaMatch (1). Downstream packages import via `@importFrom TaxaTools %||%`. |
| 2026-04-15 | *(Session 57 — new)* | `is_valid_species_name()` | TaxaTools | function | Species binomial validator (rejects sp., cf., aff., uncultured). Moved from internal `.is_valid_species_name()` in TaxaLikely + TaxaAssign. |
| 2026-04-15 | *(Session 57 — new)* | `barcode_length_defaults`, `resolve_barcode_lengths()` | TaxaTools | exported data + function | Barcode marker → bp length lookup. Moved from 3 internal copies in TaxaLikely, TaxaMatch, TaxaAssign. |
| 2026-04-15 | *(Session 57 — delete)* | `combine_occurrence_sources()` | TaxaFetch | function | Dead code; superseded by `rename_cols()` + `stack_occurrences()` (Session 19). File + Rd deleted; @seealso refs updated. |
| 2026-04-15 | *(Session 57 — delete)* | 5 stale inst/ files | TaxaFetch + TaxaLikely | workflow files | `TaxaFetch_workflow copy.R`, `migrate_prompt_api.R`, `habitat_scheme_workflow.R`, `TaxaLikely_workflow.R` (monolithic). |
| 2026-04-15 | *(Session 57 — cleanup)* | 22 empty `globalVariables(character(0))` removed | 6 packages | dead code | Convention: omit entirely from files with no NSE references. |
| 2026-04-16 | *(Session 58 — new)* | `build_priors()` | TaxaExpect | function | High-level wrapper: GBIF fetch → habitat → grid → model → priors → backbone translation (~18 calls → 1). TaxaFetch, TaxaHabitat, TaxaTools added to Suggests. |
| 2026-04-16 | *(Session 58 — new)* | `run_bayesian_pipeline()` | TaxaAssign | function | High-level wrapper: TaxaLikely likelihoods + TaxaExpect priors → full Bayesian assignment (~10 calls → 1). TaxaLikely added to Suggests. |
| 2026-04-16 | *(Session 58 — new)* | `run_llm_pipeline()` | TaxaAssign | function | High-level wrapper: LLM-shortcut workflow (~7 calls → 1); optional auto-context, unreferenced detection, report generation. |
| 2026-04-17 | *(Session 59 — polish)* | Test coverage expanded | All packages | tests | New test files: TaxaTools (rank_utils, barcode_utils, null_coalesce), TaxaHabitat (assign_habitat_biological), TaxaAssign (join_priors, update_prior, integration), TaxaLikely (fetch). 28 cross-package integration tests in TaxaAssign. |
| 2026-04-17 | *(Session 59 — new)* | 8 vignettes | All packages | vignettes | One per package + ecosystem overview in TaxaAssign. knitr/rmarkdown added to Suggests; VignetteBuilder: knitr added to all DESCRIPTION files. |
| 2026-04-17 | *(Session 59 — fix)* | DESCRIPTION text | TaxaTools + TaxaAssign | metadata | TaxaTools Description rewritten (was "This package..."); TaxaAssign Title changed to noun phrase, Description rewritten (was "TaxaAssign contains..."). CRAN-compliant phrasing. |
| 2026-04-17 | *(Session 59 — fix)* | `.Rbuildignore` | All packages | build | `.Rhistory`, `.DS_Store` added to all 7 packages. Top-level .rds/.csv files excluded in TaxaMatch, TaxaLikely, TaxaAssign. All packages now pass `--as-cran` with 0 notes. |
| 2026-04-17 | *(Session 59 — fix)* | LaTeX `\$` in Rd | TaxaFetch | bug fix | `search_literature.Rd` had escaped `\$`; fixed in roxygen source. |
| 2026-04-28 | *(Session 60 — new)* | TaxaFlag created | Ecosystem | package | Post-assignment anomalous detection flagging: contamination (lab/field blanks), allochthonous transport, taxonomic scope, handler artifacts. 6 planned exports + 1 internal helper. |
| 2026-04-28 | *(Session 60 — fix)* | `build_priors()` parameter fixes | TaxaExpect | bug fix | `taxa` param: data-frame-only (removed `taxa_rank`); `bbox` → `geometry`; `taxa` → `taxon_list`; `point_id` created before habitat assignment; `create_taxon_names()` uses `intersect(rank_system, names(df))`. |
| 2026-04-28 | *(Session 60 — new)* | `.resolve_site()` + `.latlon_to_grid()` | TaxaAssign | function | Site resolution utilities: lat/lon → nearest grid_id from taxaexpect_priors; multi-site support via data frame. |
| 2026-04-28 | *(Session 60 — new)* | `.run_consensus_and_report()` | TaxaAssign | function | Shared internal helper for consensus → empirical Bayes → optional report; used by both `run_bayesian_pipeline()` and `run_llm_pipeline()`. |
| 2026-04-29 | *(Session 61 — new)* | `remove_flagged_references()` | TaxaLikely | function | Remove mislabeled accessions from match_df using `flag_reference_errors()` output. Handles version suffix stripping. Optional `remove_unverified_singletons` param. |
| 2026-04-29 | *(Session 61 — new)* | `reference_errors` slot in `model_params` | TaxaLikely | interface | `train_likelihood_model()` now stores the error list in `model_params$reference_errors`; travels with the model object. |
| 2026-04-29 | *(Session 61 — enhancement)* | `run_bayesian_pipeline()` auto-filters errors | TaxaAssign | function | Stage 0: auto-reads `model_params$reference_errors` and removes flagged accessions from match_df before evaluating likelihoods. |
| 2026-04-29 | *(Session 61 — new)* | `reference_errors` param | TaxaAssign | `run_llm_pipeline()` | Optional data frame for error filtering in LLM workflow; accepts `model_params$reference_errors`. |
| 2026-04-29 | *(Session 61 — enhancement)* | `main_habitat` optional in `site` param | TaxaAssign | `.resolve_site()` + `.latlon_to_grid()` | `main_habitat` no longer required; auto-selects habitat with most prior rows at resolved grid_id. Falls back to auto-select when specified habitat not available. |
| 2026-04-29 | *(Session 61 — enhancement)* | `rank_system` auto-detection | TaxaLikely | `train_likelihood_model()` + `evaluate_likelihoods()` | Default `NULL` auto-detects from `.x`-suffixed columns (training) or column names (evaluation). Prevents rank mismatch errors. |
| 2026-04-29 | *(Session 61 — new)* | `model_rank_system` param | TaxaAssign | `run_bayesian_pipeline()` | Separates model ranks (from match_df columns) from taxonomy ranks (for consensus LCA). Auto-detected by default. |
| 2026-04-29 | *(Session 61 — fix)* | `expand_unreferenced_hypotheses()` empty unreferenced_df | TaxaAssign | bug fix | Early return now drops all H2/H3 rows when unreferenced_df is empty (previously returned them unchanged, causing downstream NA posteriors). |
| 2026-04-29 | *(Session 61 — fix)* | `join_priors()` taxonomy fill | TaxaAssign | bug fix | New `taxonomy_lookup` param fills taxonomy columns from match_df reference taxonomy; derives genus from species binomials. Fixes all-NA taxonomy in posteriors. |
| 2026-04-29 | *(Session 61 — enhancement)* | Pipeline optimizations A-C in `run_bayesian_pipeline()` | TaxaAssign | function | A: audit only genera in H2/H3 rows; B: pre-filter unreferenced_df to relevant genera/families; C: pre-filter priors to site + Tier 3 rows. ~16% speedup, 100% output agreement. |
| 2026-04-30 | *(Session 62 — new)* | Habitat scheme messaging in `build_priors()` | TaxaExpect | function | Stage 2 prints scheme label + how to change; `attr(output, "habitat_scheme")` attached to return value. |
| 2026-04-30 | *(Session 62 — enhancement)* | `.latlon_to_grid()` row counts in auto-select message | TaxaAssign | function | Auto-select message now shows per-habitat row counts: `"prior rows: Marine (847), Freshwater (356)"`. |
| 2026-04-30 | *(Session 62 — new)* | Species-habitat consistency check in `run_bayesian_pipeline()` | TaxaAssign | function | After site resolution, warns if <50% of candidate taxa have non-zero priors at resolved habitat. Suggests `habitat_scheme = 'IUCN_L1'` or coordinate review. |
| 2026-04-30 | *(Session 63 — new)* | `flag_contaminant()` + `.compute_contaminant_scores()` | TaxaFlag | function | Proportion-based control comparison; `control_samples` or `sample_type_col`; per-taxon summary output; `contaminant_type` param for lab/field/positive control. |
| 2026-04-30 | *(Session 63 — new)* | `flag_handler()` + `.parse_datetimes()` | TaxaFlag | function | Temporal proximity flagging; auto-parses datetime formats; per-group min/max; `handler_taxa` filter. Placeholder for camera trap data. |
| 2026-04-30 | *(Session 63 — new)* | `review_assignments()` + 3 internal helpers | TaxaFlag | function | LLM expert review: 8 structured columns (habitat, geography, scope, contaminant, alternatives, lower_hypotheses, confidence, comment). Batched calls; graceful fallback. |
| 2026-04-30 | *(Session 63 — dropped)* | `combine_flags()` | TaxaFlag | function | Users should weight flags themselves; dropped as low-value. |
| 2026-04-30 | *(Session 63 — dropped)* | `flag_detections()` | TaxaFlag | function | Convenience wrapper dropped; workflow scripts are more transparent. |
| 2026-05-01 | *(Session 64 — fix)* | `pdf_path` added to `pdf_structure` return | TaxaFetch | `screen_pdf_structure()` | Was missing; downstream `call_anthropic_api_pdf()` received NULL, failing validation. |
| 2026-05-01 | *(Session 64 — fix)* | subprocess PDF rendering via `callr` | TaxaFetch | `.render_pdf_pages()` | Corrupt PDF pages segfault poppler/pdftools at C level; `callr::r()` isolates each page render so crashes skip the page instead of killing R. `callr` added to Suggests. |
| 2026-05-01 | *(Session 64 — resolved)* | ReefCheck + Reef Life Survey | TaxaFetch | investigation | Both already in GBIF (RLS global reef fish, RCCA, Reef Check Taiwan); no separate fetch functions needed. |
| 2026-05-01 | *(Session 64 — planned)* | Distributed report architecture | Ecosystem | design | Per-package `report_*()` functions + `report_params` attributes; citations captured at TaxaFetch/TaxaExpect level before aggregation. Planned for Session 65. |
| 2026-05-02 | *(Session 65 — new)* | `new_report_section()` + `assemble_report()` | TaxaTools | function | S3 `report_section` class + assembler; `print`/`format` methods; pipeline-ordered assembly with deduplicated citations. File: `R/report_section.R`. |
| 2026-05-02 | *(Session 65 — new)* | `report_fetch()` | TaxaFetch | function | Summarizes data acquisition: sources, bbox, year range, citations from `bibliographicCitation` column. |
| 2026-05-02 | *(Session 65 — new)* | `report_match()` | TaxaMatch | function | Summarizes sequence matching: n_samples, score distribution, marker, method. |
| 2026-05-02 | *(Session 65 — new)* | `report_likelihood()` | TaxaLikely | function | Summarizes likelihood model: n_species, AIC, anchoring, mislabel detection. |
| 2026-05-02 | *(Session 65 — new)* | `report_habitat()` | TaxaHabitat | function | Summarizes habitat assignment: scheme, n_taxa, dominant habitat. |
| 2026-05-02 | *(Session 65 — new)* | `report_priors()` | TaxaExpect | function | Summarizes prior estimation: grid cells, tier breakdown, citations propagated from occurrences. |
| 2026-05-02 | *(Session 65 — new)* | `report_assign()` | TaxaAssign | function | Summarizes taxonomic assignment: workflow type, resolution rate, posterior/score stats. Lightweight companion to `generate_report()`. |
| 2026-05-02 | *(Session 65 — new)* | `report_flags()` | TaxaFlag | function | Summarizes quality flagging: auto-detects flag types present, counts flagged assignments. |
| 2026-05-02 | *(Session 65 — enhancement)* | `report_params` attribute on `stack_occurrences()` | TaxaFetch | interface | Attaches `citations` (unique `bibliographicCitation`), `n_records`, `n_sources` to output. Enables `report_fetch()` and downstream `report_priors()` to propagate citations. |
| 2026-05-02 | *(Session 65 — enhancement)* | `report_params` attribute on `build_priors()` | TaxaExpect | interface | Attaches `citations` (from occurrence data + supplemental), `n_occurrence_records`, `habitat_scheme` to output list. Enables `report_priors()` to propagate citations through aggregation. |
| 2026-05-02 | *(Session 65 — enhancement)* | `report_params` attribute on `blast_sequences()` | TaxaMatch | interface | Attaches `method` (remote/local BLAST), `database`, `min_score`, `n_samples`. Auto-read by `report_match()`. |
| 2026-05-02 | *(Session 65 — enhancement)* | `report_params` attribute on `fetch_gbif_occurrences()` | TaxaFetch | interface | Attaches `source`, `n_keys`, `n_records`, `geometry` (WKT), `year_range`. Auto-read by `report_fetch()` even without stacking. |
| 2026-05-03 | *(Session 66 — fix)* | `purrr::map_dfr()` → `lapply() \| bind_rows()` | TaxaAssign | bug fix | Deprecated since purrr 1.0.0; purrr removed from Imports entirely. |
| 2026-05-03 | *(Session 66 — fix)* | `$flag` → `$error_type` in `report_likelihood()` | TaxaLikely | bug fix | Silent data bug: always reported 0 mislabeled references because `$flag` column didn't exist. |
| 2026-05-03 | *(Session 66 — fix)* | `return()` inside `tryCatch` in `audit_barcode_coverage()` | TaxaLikely | bug fix | `return()` exits enclosing function, not tryCatch block; replaced with bare expression values. |
| 2026-05-03 | *(Session 66 — fix)* | `stop()` missing `sprintf()` in `review_assignments()` | TaxaFlag | bug fix | Error message showed literal `%s` instead of column name. |
| 2026-05-03 | *(Session 66 — fix)* | TaxaTools moved from Suggests to Imports | TaxaFlag | dependency | Used unconditionally by `report_flags()` and as default in `review_assignments()`. |
| 2026-05-03 | *(Session 66 — fix)* | `requireNamespace("TaxaTools")` guards | TaxaExpect + TaxaAssign | bug fix | Added to `report_priors()` and `report_assign()` (TaxaTools in Suggests). |
| 2026-05-03 | *(Session 66 — fix)* | `min()` crash guard in `compute_moran_basis()` | TaxaExpect | bug fix | `min(diffs[diffs > 1e-6])` errors on empty vector when all coordinates collapse; falls back to 1.0. |
| 2026-05-03 | *(Session 66 — cleanup)* | Dead code + stale refs across ecosystem | Multiple | cleanup | Dead `purrr::map_dfr`, dead merge in `review_assignments()`, dead `lo` logic in normalize.R, stale `@seealso` in `flag_contaminant()`, unnecessary `globalVariables()`, "missing" → "unreferenced" in `interpret_model()`. |
| 2026-05-03 | *(Session 66 — fix)* | Vignette parameter names corrected | TaxaFlag | docs | `data→df`, `count_col→reads_col`, `window_minutes→interval_minutes` in quality-flagging.Rmd. |
| 2026-05-03 | *(Session 66 — fix)* | Ecosystem vignette updated for TaxaFlag | TaxaAssign | docs | taxaid-ecosystem.Rmd: "seven" → "eight" packages; TaxaFlag added to pipeline diagram, installation list, and packages table. |
| 2026-05-04 | *(Session 67 — new)* | DISCLAIMER.md + code.json | All packages | USGS compliance | Provisional disclaimer in all 8 package roots; code.json email filled; .Rbuildignore updated. |
| 2026-05-04 | *(Session 67 — move)* | lme4, rentrez, xml2 → Suggests | TaxaLikely | dependency | All three already had `requireNamespace()` guards; `@importFrom xml2` removed. Reduces install footprint. |
| 2026-05-04 | *(Session 67 — move)* | leaflet, shiny, miniUI → Suggests | TaxaExpect | dependency | Only used in `plot_theta_map_interactive()` which already had `requireNamespace()` guards. |
| 2026-05-04 | *(Session 67 — fix)* | 3 stale `@seealso` cross-refs | TaxaExpect | docs | `recommend_spatial_grids_predictive()` → `optimize_grid_size()`; `add_pca_covariates()` removed; `select_habitat_outliers()` removed. |
| 2026-05-04 | *(Session 67 — breaking)* | `llm_fn` default → NULL | TaxaAssign | 4 functions | `assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`, `suggest_unreferenced_species()`: default changed from `TaxaTools::call_anthropic_api` to `NULL`. Runtime resolution via `.resolve_llm_fn()`. |
| 2026-05-04 | *(Session 67 — new)* | `.resolve_llm_fn()` | TaxaAssign | internal helper | NULL-default resolver in `R/site_utils.R`: returns user function or `TaxaTools::call_anthropic_api`; clear error if TaxaTools not installed. |
| 2026-05-04 | *(Session 67 — new)* | `test-run_pipelines.R` | TaxaAssign | tests | 10 offline input validation tests for `run_bayesian_pipeline()`, `run_llm_pipeline()`, `.resolve_llm_fn()`. |
| 2026-05-05 | *(Session 68 — new)* | TaxaWizard package | Ecosystem | package | Conversational LLM workflow designer: stateless engine, CLI chat, RStudio Viewer gadget, triple-mode output (.R, .md, app). |
| 2026-05-05 | *(Session 68 — new)* | `workflow_engine()` | TaxaWizard | function | Stateless core: history + metadata -> structured JSON. |
| 2026-05-05 | *(Session 68 — new)* | `workflow_chat()` | TaxaWizard | function | CLI readline() interview loop. |
| 2026-05-05 | *(Session 68 — new)* | `workflow_fix()` | TaxaWizard | function | Resume conversation after script error; interactive paste mode (no args). Saves corrections to `~/.taxaworkflow/corrections.json`. |
| 2026-05-05 | *(Session 68 — new)* | `workflow_gadget()` | TaxaWizard | function | RStudio Viewer pane chat via `shiny::runGadget()`. |
| 2026-05-05 | *(Session 68 — new)* | Generated script features | TaxaWizard | output | Checkpoint/resume (per-step RDS), auto-error-catch (tryCatch + workflow_fix), debug mode (subset to 20 rows). |
| 2026-05-05 | *(Session 68 — new)* | `context.R` | TaxaWizard | internal | workflow_context.json persistence + `~/.taxaworkflow/corrections.json` learning system. |
| 2026-05-05 | *(Session 68 — fix)* | All 8 metadata JSONs audited | TaxaWizard | metadata | 13 wrong param names, 2 wrong defaults, 1 wrong package corrected; missing functions/required params added. |
| 2026-05-06 | *(Session 69 — redesign)* | Graph-based workflow engine | TaxaWizard | architecture | Three-phase engine replaces monolithic prompt. `inst/graph/workflow_graph.json` (20 nodes, 22 edges) + 22 code snippets. `.compute_paths()` backward recursive search. Phase-specific prompts (~4-7K tokens each vs ~15K+ monolithic). |
| 2026-05-06 | *(Session 69 — new)* | `R/graph.R` | TaxaWizard | internal | `.load_graph()`, `.compute_paths()`, `.describe_paths()`, `.get_path_context()`, `.build_phase_prompt()`, `.describe_node_types()` + 6 helpers. |
| 2026-05-06 | *(Session 69 — new)* | 4 phase prompt templates | TaxaWizard | prompts | `phase_classify.md`, `phase_path_select.md`, `phase_parameterize.md`, `phase_error_fix.md` in inst/prompts/. |
| 2026-05-06 | *(Session 69 — redesign)* | `workflow_engine()` three-phase | TaxaWizard | function | `.detect_phase()` from history; phase-specific prompt via `.build_phase_prompt()`. Full JSON stored in assistant history. |
| 2026-05-06 | *(Session 69 — enhancement)* | `workflow_fix()` diagnostic-first | TaxaWizard | function | `.parse_error_context()` extracts step/edge; targeted error_fix prompt with full param docs; auto-mode conservative instruction. |
| 2026-05-06 | *(Session 70 — new)* | `workflow_create()` | TaxaWizard | function | Unified entry point merging `workflow_chat()` + `workflow_gadget()`. `mode` param: auto/browser/viewer/console. Default model `claude-sonnet-4-6`. |
| 2026-05-06 | *(Session 70 — deprecate)* | `workflow_chat()` | TaxaWizard | function | Deprecated thin wrapper → `workflow_create(mode = "console")`. |
| 2026-05-06 | *(Session 70 — deprecate)* | `workflow_gadget()` | TaxaWizard | function | Deprecated thin wrapper → `workflow_create(mode = "viewer")`. |
| 2026-05-06 | *(Session 70 — repurpose)* | `workflow_app()` | TaxaWizard | function | Repurposed: now takes a generated .R script path → Shiny app (placeholder). Previously was a placeholder Shiny chat UI. |
| 2026-05-06 | *(Session 70 — fix)* | Snippet column casing | TaxaWizard | snippets | 4 snippets gain rank column lowercasing loop after `detect_ranks()` (user data has `Family` not `family`). |
| 2026-05-06 | *(Session 70 — fix)* | Snippet consensus column names | TaxaWizard | snippets | `consensus_to_reviewed.R` + `consensus_to_flagged.R` hardcode `consensus_taxon`/`consensus_rank` (LLM was guessing wrong names). |
| 2026-05-06 | *(Session 70 — fix)* | Debug subsetting by sample_id | TaxaWizard | output | Generated scripts subset by first N sample_ids (not first N rows). Prevents empty high-score sets in match data. |
| 2026-05-06 | *(Session 70 — fix)* | Generated script scoping | TaxaWizard | output | Steps use `quote({...})` + `eval(envir = parent.frame())` instead of `function() {...}` closures. Variables visible across steps. |
| 2026-05-06 | *(Session 70 — fix)* | JSON parser last-first search | TaxaWizard | api | Parser tries all top-level `{...}` blocks from last to first; LLM thinking text before JSON no longer confuses parser. |
| 2026-05-06 | *(Session 70 — enhancement)* | Viewer/browser modes | TaxaWizard | UI | `dialogViewer` → `paneViewer`/`browserViewer`; scroll fix via custom message handler + absolute-positioned chat-log; user guidance messages. |
| 2026-05-07 | *(Session 71 — rename)* | TaxaWorkflow | TaxaWizard | package | Package renamed: "workflow wizard" pattern better describes the guided interview → code generation UX. All R source, DESCRIPTION, tests, CLAUDE.md updated. Directory rename deferred to user (requires RStudio project update). |
| 2026-05-07 | *(Session 71 — fix)* | Phase classify prompt | TaxaWizard | prompts | Added CRITICAL DISAMBIGUATION section: "taxa" vs "occurrences" (user has names vs already has data); "match_df" vs "consensus_df" (scores vs resolved IDs). Fixes misclassification of "map species X using GBIF" as occurrences input. |
| 2026-05-07 | *(Session 71 — fix)* | "Thinking" indicator | TaxaWizard | UI | Client-side JS shows "Thinking..." with pulse animation immediately on Send click (bypasses Shiny's blocked event loop during synchronous engine call). |
| 2026-05-07 | *(Session 71 — enhancement)* | Exit guidance messages | TaxaWizard | UI | Browser/viewer modes now print "press Stop to exit chat, then source script" guidance on launch. |
| 2026-05-11 | *(Session 72 — breaking)* | `verify_taxon_names()` NCBI direct bypass | TaxaTools | function | When `backbone_id = 4`, bypasses GlobalNames entirely; uses batched `entrez_search()` + `entrez_fetch(db="taxonomy")` XML parsing. Synonym fallback via `[All Names]`. 100% species-level accuracy (vs ~70% GlobalNames). `rentrez` + `xml2` added to Suggests. |
| 2026-05-11 | *(Session 72 — new)* | `.verify_via_ncbi()` + `.parse_ncbi_lineage_xml()` + `.ncbi_batch_summary()` | TaxaTools | internal helpers | Direct NCBI taxonomy query pipeline: batched search → XML lineage → pipe-delimited path/ranks compatible with `change_backbone()`. |
| 2026-05-11 | *(Session 72 — new)* | `.recover_higherrank()` | TaxaFetch | internal function | When `name_backbone()` returns HIGHERRANK with rank jump >1 level, falls back to `name_lookup()` with rank constraint. Rank-agnostic. |
| 2026-05-11 | *(Session 72 — fix)* | `build_priors()` rank-safety filter | TaxaExpect | function | Stage 1 filters HIGHERRANK matches >1 level coarser than input; Layer 2 fallback re-queries at finer rank. Fixes Cyprinidae -> Animalia (usageKey=1) flooding priors with 410 families. |
| 2026-05-11 | *(Session 72 — new)* | `.recover_demoted_species()` | TaxaExpect | internal function | Interim fix for GlobalNames species demotion; now superseded by NCBI direct bypass but retained as safety net. |
| 2026-05-11 | *(Session 72 — fix)* | `primer_to_locus` mapping | TaxaLikely | `.build_search_term()` | Primer names OR'd with underlying gene (MiFish->12S, Teleo->12S, Leray->COI). Fixed 0-hit results for Fundulidae/Anatidae. |
| 2026-05-11 | *(Session 72 — enhancement)* | `join_priors()` string shortcut | TaxaAssign | function | Bare grid_id string auto-selects best habitat from priors. |
| 2026-05-11 | *(Session 72 — fix)* | `lik_prior_to_post.R` snippet rewrite | TaxaWizard | snippet | Uses `{{lat}}`, `{{lon}}`, `{{main_habitat}}` with inline grid resolution instead of `{{site}}`. |
| 2026-05-11 | *(Session 72 — fix)* | `phase_parameterize.md` site guidance | TaxaWizard | prompt | Added lat/lon/habitat guidance for site resolution; `search_radius_deg` guidance; `target_backbone_id` guidance. |
| 2026-05-14 | *(Session 73 — new)* | `min_phi` param | TaxaExpect | `generate_full_priors()` + `build_priors()` | Phi floor (default 2) prevents modelled priors from becoming so diffuse that MC posteriors are unstable. Applied after phi cap. |
| 2026-05-14 | *(Session 73 — new)* | Modelled-species dark diversity floor | TaxaAssign | `join_priors()` | Species with non-NA alpha but prior_mean below dark diversity mean are promoted to dark fallback. Prevents habitat-mismatched modelled species from losing to unobserved species. |
| 2026-05-14 | *(Session 73 — fix)* | `clean_taxon_names()` accepts factors | TaxaTools | function | `is.factor()` → `as.character()` coercion before validation. Match data columns are often factors. |
| 2026-05-14 | *(Session 73 — fix)* | `finest_rank` scoping bug | TaxaLikely | `fetch_reference_sequences()` | Variable defined inside per-taxon tryCatch but referenced after loop. Added definition before final message. |
| 2026-05-14 | *(Session 73 — enhancement)* | Species column cleaning in 5 snippets | TaxaWizard | snippets | `match_to_taxa`, `match_to_consensus_score/llm/bayes`, `model_match_to_lik` all call `clean_taxon_names()` on species column before `create_taxon_names()`. Handles subspecies, hybrids, sp./cf. from BLAST. |
| 2026-05-14 | *(Session 73 — new)* | `search_rank` param | TaxaExpect | `build_priors()` | Configurable taxonomic rank for GBIF queries (default "family"). `.translate_to_gbif()` aggregates to search_rank. |
| 2026-05-14 | *(Session 73 — new)* | `max_coord_uncertainty` param | TaxaExpect | `build_priors()` | Exposed for `filter_gbif_quality()` (default 500m). Species purge warnings when taxa lose ≥80% or 100% of records. |
| 2026-05-14 | *(Session 73 — enhancement)* | `join_priors()` lat/lon + NULL default | TaxaAssign | function | `site` accepts `list(lat, lon)` via `.latlon_to_grid()`; NULL default reads `attr(priors, "search_center")` from `build_priors()`. Improved missing grid_id warnings with nearest-grid suggestion. |
| 2026-05-14 | *(Session 73 — enhancement)* | `fetch_reference_sequences()` resilience | TaxaLikely | function | Per-taxon tryCatch so NCBI rate-limit errors skip one taxon with warning instead of crashing. `cache_dir` default changed from NULL to `tempdir()`. |
| 2026-05-15 | *(Session 74 — fix)* | `taxa_per_call` default 30 → 15 | TaxaFlag | `review_assignments()` | 30 taxa × 8 JSON fields exceeded `call_anthropic_api()` 3000 max_tokens; 2 of 3 batches truncated mid-JSON. |
| 2026-05-15 | *(Session 74 — new)* | `.recover_truncated_json()` | TaxaFlag | internal helper | Salvages complete JSON objects from truncated LLM responses by walking backward through `}` positions. |
| 2026-05-15 | *(Session 74 — fix)* | Fence-stripping greedy → lazy regex | TaxaFlag | `.parse_review_response()` | `(?s).*```  ` → `(?s).*?```  ` — same PCRE footgun as Session 33. |
| 2026-05-15 | *(Session 74 — new)* | Script continuation/append mode | TaxaWizard | `R/output.R` | `.find_existing_script()` (today-only), `.append_to_script()` (step renumbering, library dedup, param dedup). `is_continuation` flag in engine. |
| 2026-05-15 | *(Session 74 — fix)* | `sample_id`/`score` rename in 3 snippets | TaxaWizard | snippets | `match_to_consensus_score/llm/bayes` now rename ESVId→sample_id, PercMatch→score before consensus calls. |
| 2026-05-15 | *(Session 74 — enhancement)* | Chat UI improvements | TaxaWizard | `R/create.R` | CSS flex layout anchors messages near input; Enter-to-send via JS keydown handler. |
| 2026-05-18 | *(Session 75 — new)* | `workflow_app()` fully implemented | TaxaWizard | `R/shiny.R` | Script-to-Shiny converter: parses params (10 types) + steps, writes standalone `app.R` with widgets, progress bar, log panel, results table, download buttons. |
| 2026-05-18 | *(Session 75 — new)* | 7 internal helpers for `workflow_app()` | TaxaWizard | `R/shiny.R` | `.parse_workflow_script()`, `.extract_libraries()`, `.extract_params()`, `.classify_param()`, `.extract_steps()`, `.build_app_code()`, `.widget_code()`, `.param_assembly_line()`, `.app_ui()`, `.app_server()`. |
| 2026-05-18 | *(Session 75 — fix)* | Log panel output binding | TaxaWizard | `R/shiny.R` | Raw `tags$pre(id=...)` replaced with `textOutput()` inside styled `div` — raw HTML element wasn't a Shiny output binding, so `renderText` never reached the browser. |
| 2026-05-18 | *(Session 75 — fix)* | `.run_step` scoping in generated app | TaxaWizard | `R/shiny.R` | `.run_step` injected into `env` via `assign()` — `env` has `parent = globalenv()` and couldn't see app-scope function definitions. |
| 2026-05-18 | *(Session 75 — fix)* | List column crash in `renderTable` | TaxaWizard | `R/shiny.R` | Added `vapply(toString)` coercion for list-type columns before display. |
| 2026-05-18 | *(Session 75 — new)* | Known parameter labels | TaxaWizard | `R/shiny.R` | `.widget_code()` lookup maps 20+ common TaxaWizard param names to descriptive labels with examples (e.g., `date` → "Sample date or year range"). |
| 2026-05-18 | *(Session 75 — new)* | Prompt rule 22: no hardcoded literals | TaxaWizard | `inst/prompts/phase_parameterize.md` | Step code must reference parameter variable names (`min_score = min_score`), never hardcode values (`min_score = 97`). Essential for Shiny widget functionality. |
| 2026-05-18 | *(Session 76 — new)* | `annotate_script()` | TaxaWizard | function | Guided annotation of generic R scripts for Shiny conversion. Self-guided (3 readline questions) or LLM-guided (1 confirmation). |
| 2026-05-18 | *(Session 76 — new)* | `.segment_script()` | TaxaWizard | internal | Pure R parsing via `parse(keep.source=TRUE)`: libraries, param candidates (top-level literals), step candidates (comment-grouped blocks). |
| 2026-05-18 | *(Session 76 — new)* | `annotate` param on `workflow_app()` | TaxaWizard | function | `"auto"` (default), `"self"`, `"llm"`, `"none"`. Auto tries TaxaWizard parsing first, falls back to annotation. |
| 2026-05-18 | *(Session 76 — new)* | `inst/prompts/annotate_script.md` | TaxaWizard | prompt | LLM prompt template for script annotation: identifies parameters and steps, returns structured JSON. |
| 2026-05-19 | *(Session 77 — new)* | `census_genus_species()` | TaxaTools | function | GBIF backbone census: enumerate described species per genus/family via `rgbif::name_usage(children)`. `match_species` param computes reference completeness (complete/singleton_missing/incomplete). Higher-rank recursion supported. `rgbif` added to Suggests. |
| 2026-05-19 | *(Session 77 — new)* | `census_genera` param | TaxaExpect | `build_priors()` | Default TRUE. Queries GBIF backbone for described species in each genus present in occurrence data. Census attached as `attr(output, "gbif_genus_census")`. |
| 2026-05-19 | *(Session 77 — new)* | Stage 1b: three-tier H2 logic | TaxaAssign | `run_bayesian_pipeline()` | Uses GBIF census from priors attribute: suppress H2 for complete genera, rename H2 for singleton-missing genera, keep generic H2 for incomplete genera. GBIF species list fed to `audit_barcode_coverage(species_list=)`. |
| 2026-05-19 | *(Session 77 — breaking)* | `main_habitat` now required | TaxaAssign | `.latlon_to_grid()`, `join_priors()`, `run_bayesian_pipeline()` | Habitat auto-selection removed. `main_habitat` must be specified in `site` param. Error messages list available habitats at the resolved grid cell with row counts and example syntax. Bare grid_id string shortcut in `join_priors()` now errors instead of auto-selecting. `search_center` NULL fallback also requires habitat. TaxaWizard snippet + prompt updated. |
| 2026-05-20 | *(Session 79 — breaking)* | `sample_id` column | `observation_id` column | TaxaMatch, TaxaLikely, TaxaAssign, TaxaFlag, TaxaWizard | column rename | L2 identifier (individual sequence/image/sound) renamed to eliminate ambiguity with L1 "sample" (collection event). ~865 occurrences across ~141 files. All R source, tests, vignettes, inst/, README, CLAUDE.md files updated. `sample_id_col` param → `observation_id_col` (TaxaMatch). `sample_col` param → `event_col` (TaxaFlag). `sample_meta` → `event_meta` (TaxaAssign). Safety: `sample_id` never reused, so missed renames produce hard errors. |
| 2026-05-20 | *(Session 79 — rename)* | `sample_id_col` param | `observation_id_col` | TaxaMatch | `standardize_match_data()` param | Renamed to match column rename. |
| 2026-05-20 | *(Session 79 — rename)* | `sample_col` param | `event_col` | TaxaFlag | `flag_contaminant()` param | This parameter identifies L1 collection events, not L2 observations. |
| 2026-05-20 | *(Session 80 — infra)* | GitHub repo created | Ecosystem | infrastructure | Public monorepo at github.com/kdlafferty/TaxaID. Homebrew + `gh` CLI installed. `.gitignore` created. Inner `.git` dirs removed from 4 packages (were causing submodule treatment). GitHub Actions CI: matrix `R CMD check --as-cran` on all 9 packages. |
| 2026-05-21 | *(Session 81 — rename)* | `habitat_observed_elsewhere` | `observed_in_habitat` | TaxaExpect | column + flag | Renamed for clarity: TRUE = species recorded in this habitat type during training; FALSE = habitat extrapolation. 43 occurrences across 9 files. |
| 2026-05-21 | *(Session 81 — new)* | `moran_k = 0` support | TaxaExpect | `build_priors()` | Moran eigenvectors now skippable by setting `moran_k = 0`. Default remains 5 (recommended). |
| 2026-05-21 | *(Session 81 — docs)* | `inst/methods_background.md` | TaxaAssign + TaxaExpect | documentation | TaxaAssign: new 10-section statistical methods background. TaxaExpect: uncertainty contrast argument, site/grid glossary, Moran default clarification, `observed_in_habitat` rename. |
