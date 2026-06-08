# CLAUDE.md — TaxaID Ecosystem
# Ecosystem-level context for Claude Code. Auto-loaded from any package subdirectory.
# Package-specific context lives in each package's own CLAUDE.md.
# Last updated: 2026-06-07 (Session 101 -- TaxaFlag vocabulary unified; posterior_consensus winner columns)

---

## ⚙️ Claude Code Behavior
- After completing any task, play a completion sound: `afplay /System/Library/Sounds/Glass.aiff`
- Always ask before making changes to multiple *existing* files at once, or before any deletions
- Run `devtools::check()` after any substantive edits to a package

---

## ⚠️ Reminder for Claude
**At the start of any session involving function changes, new functions, or name changes:
remind the user to update CLAUDE.md — especially the Function Inventory — before ending
the session. Also add significant renames to `ecosystem_docs/NAME_CHANGE_HISTORY.md`.**

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
| AZURE_OPENAI_API_KEY | Set in `~/.Renviron` — DOI employees only; requires DOI network or VPN |

---

## The TaxaID Ecosystem

| Package | Purpose | Status |
|---|---|---|
| TaxaTools | Name verification, cleaning, parsing, rank lookup, column standardisation; **LLM provider functions** (call_api, call_anthropic_api etc.); **LLM text generation** (draft_methods_text, draft_results_text); **GBIF backbone census** (census_genus_species); **Common name lookup** (common_to_scientific) | In development |
| TaxaFetch | Occurrence data acquisition (GBIF, DataONE, PDF, literature search), source combination | In development |
| TaxaHabitat | Habitat assignment via LLM, spatial QAQC; depends on TaxaTools for LLM calls | New (Session 28) |
| TaxaMatch | Sequence input (DADA2/FASTA), BLAST search, match standardization; BirdNET/image classifier ingestion | In development |
| TaxaLikely | Convert match scores to likelihoods using hierarchical Bayesian model; reference QC | New (Session 30) |
| TaxaExpect | Use occurrence and habitat data to estimate a theta prior for a taxon at a particular location | In development |
| TaxaAssign | Calculate posterior probability for a taxonomic assignment given a likelihood and a prior | Planned |
| TaxaFlag | Flag anomalous detections: contamination (lab/field blanks), allochthonous transport, taxonomic scope, handler artifacts | New (Session 60) |
| TaxaWizard | Conversational workflow designer: LLM-powered interview → .R script, .md methods, or Shiny app | New (Session 68) |

**Ecosystem logic (scored pathway):** TaxaTools cleans names → TaxaFetch fetches occurrence data → TaxaHabitat assigns habitats → TaxaMatch standardizes match data → TaxaLikely converts scores to likelihoods → TaxaExpect builds priors → TaxaAssign computes posteriors → TaxaFlag flags anomalous detections. TaxaWizard sits outside the dependency chain (generates scripts that call the other packages).

**Ecosystem logic (no-score pathway):** When match scores are unavailable or a single best candidate is returned, TaxaMatch and the likelihood model are bypassed. `TaxaLikely::unreferenced_candidates()` adds H2/H3 placeholder rows; `TaxaLikely::assign_scores()` sets likelihoods: (1) `score_type = "none"` — uniform likelihoods = 1.0, posteriors proportional to priors (morphology / expert IDs); (2) `score_type = "similarity_softmax"` — for single-score classifiers (e.g. BirdNET top-1), modulates likelihoods by classifier confidence; (3) upranked consensus — same as (1). `expand_consensus_candidates()` is deprecated (Session 99). Output feeds TaxaAssign normally.

**Dependency chain:** TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign → TaxaFlag
TaxaMatch → TaxaLikely → TaxaAssign → TaxaFlag
consensus df → TaxaLikely (unreferenced_candidates + assign_scores) → TaxaAssign → TaxaFlag
TaxaWizard: no TaxaID dependencies (uses metadata JSON files as interface)

**Package split notes:**
- Session 19: TaxaFetch split out of TaxaExpect (owns data acquisition)
- Session 28: TaxaHabitat split out of TaxaFetch (owns habitat assignment + spatial QAQC); LLM provider functions moved to TaxaTools
- Session 30: TaxaMatch scope revised to thin shell; TaxaLikely created to own score→likelihood conversion
- Session 60: TaxaFlag created for post-assignment anomalous detection flagging
- Session 68: TaxaWizard created for conversational workflow design (outside dependency chain)

**Licensing:** All packages use CC0 1.0 (public domain, per USGS policy). TaxaExpect depends on glmmTMB (GPL >= 3); source is CC0 but binary distributions bundling glmmTMB may be subject to GPL terms.

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

**⚠️ Claude Code instruction: whenever you make changes that require reinstall,**
**end your response with an explicit block like this — do not assume the user knows:**

```
## To apply these changes
1. Restart R (Session → Restart R, or Cmd+Shift+F10)
2. In the TaxaTools project: `devtools::install()`
3. [any additional packages in order]
4. Then: `library(TaxaTools)` — confirm no errors before continuing
```

**If only one package changed, list only that one. If a downstream package depends**
**on the changed package (e.g., TaxaHabitat imports TaxaTools), list both in order.**

**Quick multi-package reinstall:** `source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")`
(installs all packages in dependency order; see that file for per-package selective installs)

---

## Coding Conventions

- Native pipe `|>` throughout — never `%>%`
- `utils::globalVariables()` must be **first line** of every R file that uses NSE column names; omit entirely from files with no NSE references
- No blank lines inside `@param` roxygen blocks
- Helper/internal functions: `.` prefix + `@noRd`
- `package::function()` style for cross-package calls
- `%||%` exported from TaxaTools — never redefine in downstream packages; import via `@importFrom TaxaTools %||%`
- **`llm_fn` pattern**: LLM-calling functions accept `llm_fn = call_api` param (default via `getOption("TaxaID.llm_fn")`); users pass compatible wrapper for other providers

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

## Recent Breaking Changes (Sessions 47+)

Full history in `ecosystem_docs/NAME_CHANGE_HISTORY.md`.

| Session | Change | Package | Notes |
|---|---|---|---|
| 47 | `prior_sd` removed from `compute_posterior()` | TaxaAssign | Now uses `prior_alpha`/`prior_beta` (Beta distribution); `rbeta()` replaces `rnorm()` |
| 49 | `consensus_taxonomy()` → `posterior_consensus()` | TaxaAssign | File renamed; `score_consensus()` added as conventional alternative |
| 52 | `clean_taxon_names()` now length-preserving | TaxaTools | Invalid names → `NA` instead of dropped; add `|> na.omit() |> unique()` for old behavior |
| 56 | `taxonomy_ranks` / `rank_order` → `rank_system` | TaxaTools, TaxaMatch, TaxaAssign | Harmonized param name across ecosystem |
| 72 | `verify_taxon_names()` NCBI direct for backbone_id=4 | TaxaTools | Bypasses GlobalNames; uses batched NCBI taxonomy XML |
| 77 | `main_habitat` required in `join_priors()` / `run_bayesian_pipeline()` | TaxaAssign | Auto-selection removed; error lists available habitats + row counts |
| 79 | `sample_id` → `observation_id` | TaxaMatch, TaxaLikely, TaxaAssign, TaxaFlag, TaxaWizard | ~865 occurrences; `sample_id_col` → `observation_id_col`; `sample_meta` → `event_meta` |
| 82 | `options(TaxaID.llm_fn)` auto-detection | TaxaTools `.onAttach()` | Priority: Anthropic > Gemini > OpenAI; all `llm_fn` defaults use `getOption()` |
| 85 | `call_api()` generic dispatcher; `options(TaxaID.provider)` | TaxaTools | All 5 provider functions now thin wrappers; `.onAttach()` sets `TaxaID.llm_fn = call_api` |
| 87 | Xeno-canto API v2 → v3 | TaxaLikely | Requires `XC_API_KEY` env var; `fetch_reference_recordings()` updated |
| 88 | `build_reference_matrix()` → `build_sequence_matrix()` | TaxaLikely | File `R/build.R` → `R/build_sequence.R`; 36 files updated |
| 91 | `read_reference_fasta()` `taxonomy` param → NULL-default | TaxaLikely | Must supply exactly one of `taxonomy` (data frame) or `taxonomy_file` (TSV) |
| 97 | `build_acoustic_reference()`, `build_image_reference()`, `fetch_reference_recordings()` removed | TaxaLikely | Acoustic/image workflows simplified to post-classifier only; no reference download step |
| 97 | `expand_consensus_candidates()` gains `score_col` param | TaxaLikely | L(H1)=score, L(others)=1−score when score supplied (BirdNET top-1 use case) |
| 97 | `common_to_scientific()` added | TaxaTools | LLM-assisted common name → scientific name with optional backbone verification |
| 99 | `score` → `score_original` in TaxaMatch output | TaxaMatch | `standardize_match_data()` now outputs `score_original`; `.evaluate_one_query()` updated to accept it |
| 99 | `likelihood_point_est`/`_mean`/`_sd` → `score_likelihood`/`_mean`/`_sd` | TaxaLikely, TaxaAssign | Column rename across all functions, tests, workflows, docs |
| 99 | `unreferenced_candidates()`, `assign_scores()`, `model_likelihoods()`, `compute_likelihoods()` added | TaxaLikely | Unified modular pipeline; replaces separate eDNA and no-score entry points |
| 99 | `expand_consensus_candidates()` deprecated | TaxaLikely | `.Deprecated()` notice; use `unreferenced_candidates()` + `assign_scores()` |
| 100 | `score_likelihood_cov` added to `evaluate_likelihoods()` output | TaxaLikely | Coverage-adjusted point estimate: σ inflated by `1/sqrt(coverage)`; equals `score_likelihood` when coverage absent or = 1 |
| 101 | `review_assignments()` output columns renamed | TaxaFlag | `review_habitat`→`habitat_plausibility`, `review_geography`→`geographic_plausibility`, `review_scope`→`scope_plausibility`, `review_contaminant`→`contamination_risk`; values unified to `likely/possible/unlikely` (plausibility) and `low/moderate/high` (risk) |
| 101 | `flag_contaminant()` output columns renamed | TaxaFlag | `flag_{type}`→`{type}_risk`, `flag_{type}_score`→`{type}_score`, `flag_{type}_reason`→`{type}_reason`; values `"likely"`→`"low"`, `"possible"`→`"moderate"`, `"unlikely"`→`"high"` |
| 101 | `posterior_consensus()` gains winner columns | TaxaAssign | `winner_prior`, `winner_likelihood`, `winner_likelihood_cov` added to output; winner = highest-posterior hypothesis in plausible set; enables TaxaFlag to detect low-prior winners (100%-rule artifacts) |
