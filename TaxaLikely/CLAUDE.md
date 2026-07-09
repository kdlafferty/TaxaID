# CLAUDE.md -- TaxaLikely
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-06 (Session 142 -- trim_to_amplicon() now supports the real eDNA COI
# mini-barcode (Leray et al. 2013 mlCOIintF/Meyer 2003 dgHCO2198, "coi-leray"), resolving
# Session 141's flagged inosine blocker by pairing Leray's own inosine-free forward primer
# with an inosine-free reverse primer (Meyer 2003) instead of Geller et al. 2013's jgHCO2198 --
# no code changes needed here, same pattern as Session 141. See TaxaTools/CLAUDE.md's Session
# 142 note for the discriminatory-power literature review and full verification record.
# Session 141 -- trim_to_amplicon() now works out of the box for
# every mitochondrial/chloroplast marker in barcode_length_defaults (16S, COI, cytb, rbcL,
# matK, trnL), not just MiFish-12S -- TaxaTools::barcode_primer_defaults gained 6 more
# entries, each independently verified AND empirically tested against a real GenBank
# mitogenome/chloroplast genome. No code changes needed in this package -- trim_to_amplicon()
# was already generic over any barcode_term with a registered primer pair. See
# TaxaTools/CLAUDE.md's Session 141 note for the full verification record, including two real
# errors the empirical testing caught (a wrong cytb amplicon length, a matK forward/reverse
# mislabeling) that a literature-only check would have missed.
# Session 140 -- trim_to_amplicon() added: in-silico PCR
# amplicon extraction for over-length reference sequences (full mitogenomes, etc.) that
# would otherwise be excluded outright by build_sequence_matrix()'s length filter --
# implements ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md.
# Locates verified MiFish-U/E primer-binding sites (Biostrings::matchPattern(fixed =
# "subject"), both strands, mismatch-tolerant) and extracts just the amplicon; falls back
# gracefully per-sequence when a primer site can't be found or implies an implausible span.
# New TaxaTools::barcode_primer_defaults registry (MiFish-U/E only, verified against Miya
# et al. 2015 across three independent sources) + resolve_barcode_primers(). See Session
# 140 note below and TaxaTools/CLAUDE.md's own Session 140 note. Session 136 — fetch_reference_sequences() renamed to
# fetch_ncbi_reference_sequences() (old name kept as deprecated alias) now that a second
# live-API reference source exists: fetch_bold_reference_sequences(), built directly
# against BOLD's real v5 Data Portal API via httr2 (BOLD migrated off the old v3/v4 API
# the archived `bold` R package targets -- see Session 136 note below for the full
# investigation). subset_local_database() gained real PR2 support (.pr2_hierarchy, a
# fixed 9-level positional format, confirmed against real PR2 v5.1.1 data) and a MIDORI2
# license caveat. Session 135 — fetch_reference_sequences(include_location=)
# and a new fetch_xc_recording_locations() close two of the three location-metadata gaps
# flagged in ecosystem_docs/TODO_validation_benchmark.md's "Sourcing location data" section;
# see Session 135 note below. Session 133 — acoustic tau re-calibrated on a real 24-species/8-cluster/2487-window dataset; Session 128/129's tau≈1/tau≈3.6 for acoustic did NOT survive the larger sample, pooled result is tau≈0 matching image, though per-cluster results are heterogeneous; no current evidence for tau>0 as a default. Session 129 — assign_scores() score-scale bug found and fixed (unbounded scores like iNaturalist's combined_score no longer forced through a fixed 0-100 divisor); tau/score_sharpness jointly calibrated on 51 clean real photos; image resolved to tau≈0, superseding Session 128's confounded 5/6->4/6 number)

---

## Package Purpose
Converts match scores (DNA percent identity, image similarity, acoustic scores) into
likelihoods for taxonomic assignment. Takes a standardized match object (from TaxaMatch
or user-supplied) and produces per-hypothesis `score_likelihood`, `score_likelihood_mean`,
`score_likelihood_sd` columns required by TaxaAssign.

Also provides reference database quality tools:
- Detecting mislabeled reference sequences
- Auditing taxonomic completeness (identifying unreferenced taxa missing from the reference)

Part of the TaxaID ecosystem. Depends on TaxaTools for name cleaning and column standardization.

**Status: All functions written and passing devtools::check() (0 errors, 0 warnings, 0 notes).**
**Source refactored from: `~/Rscripts/eDNA/Bayesian  Workflow/Universal_Biological_Classifier_Working_2.R`**

---

## Dependency Chain

TaxaTools -> TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign / TaxaMatch -> **TaxaLikely** -> TaxaAssign

TaxaLikely depends on TaxaTools for:
- `create_taxon_names()` -- derives `taxon_name` + `taxon_name_rank` (used in evaluate.R for H2/H3 rows)

---

## Match Object Interface (Input)

The canonical match object produced by `standardize_match_data()` (TaxaMatch) or
supplied directly by the user. One row per `observation_id` x reference accession match.

| Column | Type | Required | Notes |
|---|---|---|---|
| `observation_id` | character | Yes | Unique query ID (e.g. ESVId, image hash, clip ID) |
| `score` | numeric | Yes | Raw match score (e.g. PercMatch 0-100, or similarity 0-1) |
| `taxon_name` | character | Yes | Best taxon label for this reference (from `create_taxon_names()`) |
| `taxon_name_rank` | character | Yes | Rank of `taxon_name` (e.g. "species", "genus") |
| taxonomy cols | character | Yes | e.g. `family`, `genus`, `species` -- must match `rank_system` |
| `testid` | character | No | Marker/barcode type (e.g. "MiFishU") -- retained, not modelled |
| `accession` | character | No | Reference accession -- retained, not modelled |

**Note:** Sample context (site, date, replicate) lives in a separate table and is joined
to likelihood output downstream -- it is NOT part of the match object.

---

## Likelihood Object Interface (Output -> TaxaAssign)

`evaluate_likelihoods()` returns a **named list** with two components:

**`$likelihoods`** -- one row per `observation_id` x taxon hypothesis; pass to
`filter_top_hypotheses()`, `apply_coverage_constraints()`, and
`TaxaAssign::compute_posterior()`.

| Column | Type | Description |
|---|---|---|
| `observation_id` | character | Query identifier |
| `taxon_name` | character | Hypothesized taxon (never NA) |
| `taxon_name_rank` | character | Rank of hypothesis |
| `hypothesis_type` | character | "specific_candidate", "unreferenced_species", "unreferenced_genus" |
| `score_likelihood` | numeric | Point estimate (deterministic) |
| `score_likelihood_mean` | numeric | Mean across Monte Carlo simulations |
| `score_likelihood_sd` | numeric | SD across simulations (0 if n_sims = 0) |
| `score_likelihood_cov` | numeric | Coverage-adjusted point estimate: H1 sigma inflated by `1/sqrt(coverage)`; equals `score_likelihood` when coverage absent or = 1 |

**`$unresolved`** -- rows from the original `match_df` for any `observation_id` that
produced no usable likelihoods (e.g., all candidates matched only at a rank
coarser than `rank_system` specifies). Empty data frame if none. Re-run
`evaluate_likelihoods()` on `$unresolved` with a coarser `rank_system`.

TaxaAssign joins on `taxon_name` + `taxon_name_rank`. TaxaExpect provides priors
for `unreferenced_species` and `unreferenced_genus` rows (unreferenced species priors).

---

## Function Inventory

### Reference acquisition (build reference_df)

| Function | File | Status | Description |
|---|---|---|---|
| `fetch_ncbi_reference_sequences()` | `R/fetch.R` | Written | **Renamed from `fetch_reference_sequences()` (Session 136)** — old name kept as a deprecated forwarding alias (`.Deprecated()`, matches `audit_barcode_coverage_ncbi()`'s pattern); renamed because a second live-API reference source (BOLD) was planned and the old name didn't say NCBI anywhere. Search NCBI by taxon + barcode marker, resolve taxonomy via taxid bridge, filter/downsample, download FASTA → `reference_df`. Count-first estimation; resumable via `cache_dir` (default `tools::R_user_dir("TaxaLikely","cache")`). Cache key includes `min_len`, `max_len`, `max_date` so changed parameters auto-start fresh. Per-taxon tryCatch: NCBI rate-limit errors skip one taxon with warning instead of crashing the entire run. **Session 135**: `include_location = FALSE` param — when `TRUE`, fetches each accession's full GBSeq XML record (`.fetch_locations_batched()`) and adds `lat`/`lon`/`country` columns parsed from the `source` feature's `lat_lon`/`country` qualifiers (`.parse_lat_lon()`); a genuinely separate NCBI round trip from the ESummary/taxonomy-XML fetches this function already does, neither of which carries those qualifiers. |
| `fetch_bold_reference_sequences()` | `R/fetch.R` | Written | BOLD Systems reference-fetch analog. **Session 136**: talks directly to BOLD's real, live v5 Data Portal API (`portal.boldsystems.org/api`, confirmed via its own OpenAPI spec) via `httr2` -- does NOT wrap the `bold` R package, whose `bold_seqspec()`/`bold_identify()` target BOLD's now-permanently-retired v3/v4 API. 3-stage flow: `query/preprocessor` (resolve taxon → triplet) → `query` (submit → `query_id`) → `documents/{id}/download?format=tsv` (returns full result set, no pagination needed). No server-side marker/locus filter exists in BOLD's query API (only `tax`/`geo`/`ids`/`bin`/`recordsetcode` scopes) — `barcode_term` filters client-side on the returned `marker_code` column. Location (`coord`, bracketed `"[lat, lon]"` string, parsed by `.parse_bold_coord()`; `country/ocean`) comes free with every query, unlike NCBI which needs a separate round trip. Live-tested end to end (103 real sequences across 2 taxa, 84% real coordinate coverage). Internal helpers: `.bold_resolve_taxon()`, `.bold_submit_query()`, `.bold_fetch_documents()`, `.parse_bold_coord()`. |
| `read_crabs_output()` | `R/read_crabs.R` | Written | Read CRABS internal-format database (headerless 11-column TSV) → `reference_df`. Params: `rank_system` (NULL = auto-detect from populated columns), `max_n_bases`, `require_species` (uses `TaxaTools::is_valid_species_name()`), `dereplicate` (collapse exact-duplicate seqs within species). Complementary to `flag_reference_errors()`: CRABS handles bulk QC; TaxaLikely catches mislabeling CRABS cannot detect. |
| `trim_to_amplicon()` | `R/trim_to_amplicon.R` | Written | **Session 140.** In-silico PCR: locates forward/reverse primer-binding sites in over-length `reference_df` sequences (full mitogenomes, whole-genome scaffolds) and extracts just the amplicon, instead of `build_sequence_matrix()`'s length filter discarding the whole sequence -- the fix for a poorly-sampled species whose only GenBank record is over-length losing all reference representation. Standalone stage: `fetch_ncbi_reference_sequences()` → `trim_to_amplicon()` → `build_sequence_matrix()`. Sequences already within `[min_len, max_len]` are left untouched (most purpose-cut barcode submissions already have primers stripped at deposition, so attempting a match on them would often fail even though the sequence is fine). Primers resolved via `barcode_term` (`TaxaTools::resolve_barcode_primers()`) or supplied directly (`primer_fwd`/`primer_rev`) for any marker not yet in the registry. `Biostrings::matchPattern(fixed = "subject")` (both strands, via `reverseComplement()`) -- empirically confirmed `fixed = FALSE` produces spurious matches across long N-runs in draft sequences, while `fixed = "subject"` correctly treats subject ambiguity codes literally while still interpreting the primer's own IUPAC degeneracy. `max_mismatch_rate` (default `0.15`) tolerates real SNP variation at primer-binding sites. A matched pair implying a span outside `[min_len, max_len]` is rejected as an implausible pairing rather than accepted (guards against a spurious far-apart match producing a near-original-length "amplicon"). Per-sequence graceful fallback: unmatched/implausible sequences are left unchanged (still over-length) and flagged via `amplicon_trim_note`, so they fall through to `build_sequence_matrix()`'s existing length filter exactly as before -- this function only ever rescues sequences that would otherwise be lost, never removes ones that would otherwise be kept. Live-verified on a realistic simulated 16kb mitogenome containing an embedded real MiFish-U amplicon: correctly extracted a 172bp sequence (matching Miya et al. 2015's own reported mean amplicon length exactly) that would otherwise have been dropped outright. Deliberately narrow in scope -- not a CRABS reimplementation; primer registry is populated only for verified primer sets (currently MiFish-U/E), with an unregistered marker directed to supply primers directly or pre-trim with CRABS. Internal helper: `.extract_amplicon_one()`. **Session 141**: works out of the box for 6 more markers now that `barcode_primer_defaults` covers every mito/chloroplast marker in `barcode_length_defaults` (16S, COI, cytb, rbcL, matK, trnL) -- no code change needed here, since this function was already generic over any `barcode_term` with a registered pair. New tests confirm real, literature-verified COI-Folmer and rbcLa primer pairs correctly extract from an over-length synthetic sequence, plus a loop test covering all 6 new registry entries end-to-end. **Session 142**: now also supports `coi-leray` (the real mlCOIintF/dgHCO2198 eDNA mini-barcode) -- no code change needed, `barcode_term = "COI-Leray"` resolves through the same generic path. New test confirms correct extraction of a real, literature-verified Leray-fragment amplicon; bare `"COI"` now errors (ambiguous between `coi-folmer`/`coi-leray`) rather than guessing. |
| `read_reference_fasta()` | `R/fetch.R` | Written | Read local FASTA + taxonomy → `reference_df`. For CRUX, GenBank dumps, custom databases. `taxonomy` param accepts a data frame; new `taxonomy_file` param accepts a 2-column TSV (QIIME2/RESCRIPt/SILVA/MIDORI2 prefix-style `k__Kingdom;...` or positional `Kingdom;...`). Exactly one of `taxonomy` or `taxonomy_file` must be supplied (previously `taxonomy` was required). Internals: `.parse_taxonomy_tsv()`, `.parse_tax_string()`. |
| `subset_local_database()` | `R/subset_db.R` | Written | Filter a large local FASTA + taxonomy file (SILVA, MIDORI2, GTDB, Greengenes2, RDP, **PR2 — Session 136**) to a user-supplied taxon list. Parses taxonomy first → O(1) ID lookup via environment hash → streams FASTA in chunks; peak memory scales with matching sequences, not total database size. Supports `.gz`-compressed FASTA. Optional `max_n_bases` and `require_species` filters. Returns `reference_df`. Reuses `.parse_taxonomy_tsv()` internal. **Session 136**: added real PR2 support — PR2 uses a fixed 9-level positional taxonomy string (`domain;supergroup;division;subdivision;class;order;family;genus;species`, confirmed against a real downloaded v5.1.1 release, 240,201 records, 100% uniform) that doesn't match `.crabs_std_hierarchy`'s 7-level shape; `.parse_tax_string()` now dispatches on field count (9 → new `.pr2_hierarchy` constant) rather than bending the shared 7-level constant every other positional source relies on. Also confirmed and preserved (not stripped) PR2's `:plas` plastid-ancestry suffix. MIDORI2's license (reported CC-BY-NC in secondary sources, unconfirmed on the primary site) now flagged in `@details` as a possible conflict with this ecosystem's CC0/USGS policy. |

### Training (fit model on reference database)

| Function | File | Status | Description |
|---|---|---|---|
| `build_sequence_matrix()` | `R/build_sequence.R` | Written | Align DNA sequences (DECIPHER), compute pairwise distance matrix → pair format for `train_likelihood_model()`. Output includes `coverage` column. New params (Session 112): `filter_unnamed = TRUE` drops sequences with blank/NA finest-rank (species) label before alignment — removes spurious within-species pairs (blank == blank) that dominated 18S databases (69% of pairs); `max_seqs_per_taxon = NULL` randomly subsamples sequences per species before alignment to prevent heavily-sequenced taxa (e.g. Ovis aries) from dominating the within-species distribution. Both operate pre-alignment, reducing DECIPHER computation time. Renamed from `build_reference_matrix()` Session 88. |
| `flag_reference_errors()` | `R/train.R` | Written | Flag mislabeled references |
| `train_likelihood_model()` | `R/train.R` | Written | Full training pipeline -> `taxa_model_params` object; `anchor_perfect` param (default TRUE) injects synthetic perfect-match observations. Bivariate normal over `(score_logit, gap_logit)`. Coverage is a filter only — pass `min_coverage` to `evaluate_likelihoods()` at inference, not a model dimension. |

### Unified likelihood pipeline (new — Session 99)

| Function | File | Status | Description |
|---|---|---|---|
| `unreferenced_candidates()` | `R/unreferenced_candidates.R` | Written | Expand match_df with H2/H3/(H4) placeholder rows. Auto-detects `rank_system`. `include_unreferenced_family` param (default FALSE) adds H4 catch-all. Anchor = best-scoring taxon per observation. |
| `assign_scores()` | `R/assign_scores.R` | Written | Convert raw scores to `score_likelihood`. `score_type`: `"none"` (all rows = 1.0 uniform), `"direct"` (pass score column through unchanged; NA → 1.0; use after `restore_suppressed_candidates()` no-score path), `"probability"` (ratio-normalize H1; H2/H3 anchored at median same-genus/same-family H1 likelihood; H4 fixed at 0.05), `"similarity_softmax"` (exp-weighted, same H2/H3/H4 anchoring), `"similarity"` (adds `score_norm` only — pass to `model_likelihoods()`). **Single-H1 caveat**: for top-1 classifier output (one H1 row per observation), H2/H3 anchor = median(H1) = 1.0; score has no discriminating effect. Use multi-candidate output + `"probability"` to modulate likelihoods. **Session 129 fix**: `similarity`/`similarity_softmax` auto-detect score scale from the global max of `score_col` (no new parameter) — `max <= 100` keeps the original fixed 0-100/0-1 divisor (BLAST-style, unchanged); `max > 100` (unbounded scores, e.g. iNaturalist's `combined_score`) normalizes each observation against its own candidate range instead, since a fixed divisor was collapsing `score_likelihood` to near-uniform for that data type. `probability` was never affected (doesn't call `.normalize_scores()`). |
| `model_likelihoods()` | `R/compute_likelihoods.R` | Written | Apply bivariate-normal model to a `scored_df` from `assign_scores(score_type="similarity")`. Thin wrapper around `evaluate_likelihoods()`; adds `score_method = "bivariate_normal"`. |
| `compute_likelihoods()` | `R/compute_likelihoods.R` | Written | Orchestrating wrapper: `unreferenced_candidates()` → `assign_scores()` → `model_likelihoods()` (similarity only). Recommended high-level entry point. Returns `list($likelihoods, $unresolved)`. |

### Training-database bias correction (Session 125, revised Session 127)

| Function | File | Status | Description |
|---|---|---|---|
| `correct_training_bias()` | `R/correct_training_bias.R` | Written, wired, live-tested | Divides out an estimated training-count bias (`n_i`) from raw classifier scores before `unreferenced_candidates()`/`assign_scores()` run: `score_i / n_i^tau`. **Revised Session 127**: `tau` is now a single fixed global scalar (default `1.0`, user-tunable), not the Session 125 adaptive per-candidate `tau_i = n_i/(n_i+prior_weight)` — matches Menon et al. 2020's "logit adjustment" correction for long-tailed recognition (literature research found no support for a per-candidate adaptive exponent; the theoretically Fisher-consistent form applies one scalar uniformly). `prior_weight` parameter removed. Missing/zero counts still fall through to the uncorrected score (`tau_used = 0` for that row only) — a deliberate, documented deviation from strict logit adjustment, kept for the same practical reason as before (can't distinguish genuine rarity from a failed lookup). Overwrites `score_col` (default `"score_original"`) in place; preserves the pre-correction value in `score_uncorrected`; adds `n_used`, `tau_used` diagnostics. Pipeline placement: `raw scored_df → correct_training_bias() → unreferenced_candidates() → assign_scores()`. Unit-tested (27 expectations, synthetic fixture). **Wired into `image_acoustic_likelihood_workflow.R` Session 128** (both sections) and live-tested against real classifier output. **Resolved Session 129** (see that session's note below): the Session 128 image number was confounded by an unrelated `assign_scores()` bug; on clean, bug-fixed, 51-photo data, `tau ≈ 0` is optimal for image (correction should not be applied). **Session 133**: acoustic's Session 128/129 `tau ≈ 1`/`tau ≈ 3.6` result did NOT survive a properly powered re-test (24 species/8 confusable clusters/2487 real BirdNET detection windows, vs. the original 3-species/42-window pilot) — pooled acoustic optimum is now `tau ≈ 0` too, though per-cluster results are genuinely heterogeneous (5/8 clusters agree with `tau ≈ 0`; 2 clusters still prefer high `tau` even at ~150-170 windows each, unbracketed at the swept grid's edge). **No current real-data evidence supports `tau > 0` as a default for either data type** — the package default remains `tau = 1.0` (theoretical, Menon et al. 2020) pending a deliberate decision on whether to change it. `tau` must still be calibrated per data type (and, per Session 133, possibly per taxon cluster) — see `TaxaLikely/inst/workflows/calibrate_training_bias_tau.R` and `ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md` for full method detail. |

### Inference (apply model to query observations)

| Function | File | Status | Description |
|---|---|---|---|
| `evaluate_likelihoods()` | `R/evaluate.R` | Written | Apply model to all queries; outputs likelihood object. `verbose` param (default FALSE) logs species-specific param fallback. Output includes `score_likelihood_cov`: coverage-adjusted point estimate inflating H1 sigma by `1/sqrt(coverage)` per candidate taxon (binomial SE prior); equals `score_likelihood` when coverage column is absent or all 1. |
| `filter_top_hypotheses()` | `R/evaluate.R` | Written | Keep finest-rank candidates per query |

### Reference coverage

| Function | File | Status | Description |
|---|---|---|---|
| `infer_exclude_predicted()` | `R/infer_predicted.R` | Written | Inspects accession column of a match object to infer whether the BLAST reference excluded computationally predicted (XR_/XM_) sequences. Returns `TRUE` (no XR_/XM_ found → exclude), `FALSE` (predicted accessions present → include), or `NA` (all custom/non-NCBI accessions → cannot determine). Auto-detects accession column; strips version suffixes; reports custom accession count. Feeds directly into `audit_barcode_coverage(exclude_predicted = infer_exclude_predicted(match_obj) \%\|\|\% TRUE)`. |
| `audit_barcode_coverage()` | `R/coverage.R` | Written | **Preferred for eDNA/barcode data.** Unreferenced = described species with NO barcode sequence (cannot appear as reference match). **Reverse-search implementation** (Session 113): one genus-level NCBI nuccore query + batched `elink` → taxonomy + batched `entrez_summary`; ~4 fixed API calls per genus regardless of species count (3.25× faster than per-species queries on 18S protist/algae genera). Species enumeration: NCBI taxonomy subtree (or user `species_list`). Census: `in_reference`, `has_seqs_not_in_ref`, `unreferenced`, `is_complete`. Params: `barcode_term` (vector ok), `max_date`, `min_len`, `max_len`, `species_list`, `max_nuccore` (default 5000), `cache_dir`. Checkpoint/resume: progress saved per genus; interrupted runs resume automatically. Hyphenated genera (e.g. *Pseudo-nitzschia*) handled via hyphen→space normalization in `.genus_taxid()`. `audit_barcode_coverage_ncbi()` is a deprecated alias. |
| `audit_reference_coverage()` | `R/coverage.R` | Written | Queries NCBI taxonomy tree (all described species). Use for non-barcode libraries (images, sounds) where barcode availability is irrelevant. |
| `audit_acoustic_coverage()` | `R/coverage.R` | Written | **Acoustic/image.** Which plausible species are absent from classifier's known list? Simple set-membership check — no NCBI API. `match_df` param annotates `in_match_data`. `xc_recordings = FALSE` param (Session 119, fixed to v3 Session 125): when TRUE, queries Xeno-canto v3 API (requires `XC_API_KEY` env var) for `n_recordings` per species (1s rate limit; NA on failure or missing key). Returns `list(census, unreferenced)` matching `audit_barcode_coverage()` format. |
| `audit_inat_coverage()` | `R/coverage.R` | Written | **iNaturalist image coverage audit** (Session 119). Given a species list (prior taxa), queries iNat taxa API for each species: returns `n_observations`, `cv_model_included` (n_obs >= `cv_threshold`, default 100L), `unreferenced` list. Optional `match_df` annotates `in_match_data`. Optional `api_token` (env `INAT_API_TOKEN`; 401 → stop). 0.3s rate limit. Returns `list(census, unreferenced)` with same structure as `audit_barcode_coverage()`. Internal helpers: `.inat_species_info()`, `.xc_recording_count()`. |
| `fetch_xc_recording_locations()` | `R/coverage.R` | Written | **Session 135.** Given one or more species names, returns per-recording `species`/`xc_id`/`lat`/`lon`/`country` from Xeno-canto v3 — the same API response `audit_acoustic_coverage(xc_recordings = TRUE)` already queries via `.xc_recording_count()`, but that function only ever read `numRecordings` off the body and discarded the `recordings` array's own `lat`/`lng`/`cnt` fields. Refactored the shared HTTP call into `.xc_recordings_raw()` (zero behavior change for `.xc_recording_count()`, confirmed by its own tests) and added `.xc_recording_locations()` as the per-recording extractor this function loops over (1s/species rate limit, matching `audit_acoustic_coverage()`'s own). `xc_id` is Xeno-canto's own catalog number, not a `TaxaMatch::build_site_table()`-ready `observation_id` — mapping it to a caller's BirdNET observation-id convention is left to the caller (harness-level concern, not attempted here). |
| `apply_coverage_constraints()` | `R/coverage.R` | Written | Suppress "unreferenced_species" for fully-sampled genera |
| `expand_unreferenced_hypotheses()` | moved to TaxaAssign | — | Requires both TaxaLikely and TaxaExpect outputs; belongs at the convergence point. See `TaxaAssign/R/expand_unreferenced.R`. |

### Coverage quality calibration

| Function | File | Status | Description |
|---|---|---|---|
| `calibrate_coverage_filter()` | `R/calibrate.R` | Written | Sweep a grid of coverage thresholds over `build_sequence_matrix()` output; return per-threshold breadth + H1/H2 discrimination metrics. Key columns: `breadth`, `h1_retention`, `h2_retention`, `youden_j` (primary — maximised at Pareto-optimal threshold), `discrimination` (ratio form), `mean_h1_score`. Detects categorical coverage (≤10 unique values) and messages that J will be near-flat. Auto-detects finest rank from `.x`/`.y` column pairs via `.detect_finest_rank_col()`. |
| `coverage_threshold()` | `R/calibrate.R` | Written | Quantile-based shortcut: returns the coverage value at the `(1 − keep_frac)` quantile so that `keep_frac` of pairs are retained (default 0.95). For categorical coverage, snaps to the nearest unique value with a message showing the achieved retention fraction. |

### No-score (prior-only) pathway

| Function | File | Status | Description |
|---|---|---|---|
| `expand_consensus_candidates()` | `R/expand_consensus.R` | **Deprecated (Session 99)** | Use `unreferenced_candidates()` + `assign_scores()` instead. Deprecated with `.Deprecated()` notice in function body. |

### Score-collapse detection and restoration

| Function | File | Status | Description |
|---|---|---|---|
| `detect_suppressed_candidates()` | `R/score_collapse.R` | Written | Diagnose which pipeline suppression rule(s) are active. Three rules: `"perfect_only"` (purity_threshold fraction of qualifying obs have only scores ≥ perfect_threshold); `"max_score_ties"` (multi-row obs all show uniform score); `"best_only"` (singleton_threshold fraction of obs have exactly 1 row). `purity_threshold` (default 0.99) and `perfect_threshold` (default 100) user-settable. Returns list: rule_detected, rules, individual logicals, diagnostic counts, example_observations. |
| `restore_suppressed_candidates()` | `R/score_collapse.R` | Written | Append same-genus congeners from `reference_df` as `hypothesis_type = "suppressed_candidate"` rows. Targeting: Rules 2/3 → all observations; Rule 1 only → observations where all scores ≥ perfect_threshold. Score imputation: `delta` (default 0.5, auto-scaled 0–100 vs 0–1) subtracted from per-obs max score. No-score path: creates synthetic `score_original` column (H1 = 1.0, restored = 1.0 − delta/100); pass to `assign_scores(score_type = "direct")`. Returns match_obj with `is_restored` column. |

**Motivation:** When BLAST uses a 100-percent rule (drop all sub-perfect hits when a perfect match exists), referenced congeners are silently suppressed. `evaluate_likelihoods()` sees only one H1 candidate (singleton mode — gap uninformative) and generates only generic `unreferenced_species` H2/H3 rows. `restore_suppressed_candidates()` replaces those generic placeholders with real referenced alternatives, enabling full bivariate-normal evaluation. See *Girella simplicidens* case (Session 101/103).

### Match object cleaning and export

| Function | File | Status | Description |
|---|---|---|---|
| `remove_flagged_references()` | `R/clean.R` | Written | Remove mislabeled accessions from match_df using `flag_reference_errors()` output. Handles version suffix stripping. `remove_unverified_singletons` param (default FALSE). |
| `write_reference_fasta()` | `R/write_fasta.R` | Written | Export `reference_df` to FASTA + optional companion taxonomy TSV. FASTA header: `>{composite_id} {rank vals}` (NA ranks omitted). TSV is positional format compatible with `read_reference_fasta(taxonomy_file=)`. `rank_system` auto-detected when NULL. |
| `build_site_reference()` | `R/build_site_reference.R` | Written | High-level site-specific reference builder (DNA only). taxa list → `fetch_reference_sequences()` → optional `flag_reference_errors()` → `audit_barcode_coverage()` → `write_reference_fasta()`. Returns `list($reference_df, $errors, $census, $unreferenced)`. `output_dir` param writes `reference.fasta` + `reference_taxonomy.tsv`. |

### Diagnostics

| Function | File | Status | Description |
|---|---|---|---|
| `interpret_model()` | `R/interpret.R` | Written | Summarise trained model: expected match %, gap, per-species profiles |

### Reporting

| Function | File | Status | Description |
|---|---|---|---|
| `report_likelihood()` | `R/report_likelihood.R` | Written | Generate `report_section` summarizing model training (n_species, AIC, anchoring, mislabel detection). For `assemble_report()`. |

### Internal helpers (not exported)

| Function | File | Description |
|---|---|---|
| `.normalize_scores()` | `R/normalize.R` | Normalise raw scores to (0,1); clip for logit |
| `.prep_training_data()` | `R/train.R` | Logit-transform, compute within-species pairs + gap |
| `.evaluate_one_query()` | `R/evaluate.R` | Per-query H1/H2/H3 likelihood calculation |
| `.detect_finest_rank_col()` | `R/calibrate.R` | Auto-detect finest rank from paired `.x`/`.y` columns using `TaxaTools::standard_ranks`; used by `calibrate_coverage_filter()` |
| `.build_search_term()` | `R/fetch.R` | Construct NCBI nucleotide search query from taxon + barcode_term + dates |
| `.fetch_summaries_batched()` | `R/fetch.R` | Batched NCBI summary retrieval (accession, taxid, length); exponential backoff |
| `.fetch_taxonomy_map()` | `R/fetch.R` | Batched NCBI taxonomy XML → full lineage lookup table |
| `.fetch_fasta_batched()` | `R/fetch.R` | Batched FASTA download from NCBI nucleotide |
| `.parse_fasta_text()` | `R/fetch.R` | Parse FASTA text into data.frame(composite_id, sequence) |
| `.parse_taxonomy_tsv()` | `R/fetch.R` | Parse 2-column taxonomy TSV (QIIME2/RESCRIPt/SILVA/MIDORI2) → data frame for `read_reference_fasta(taxonomy_file=)`. Skips header rows; calls `.parse_tax_string()` on unique strings only (efficient for large files). |
| `.parse_tax_string()` | `R/fetch.R` | Parse one semicolon-delimited taxonomy string; auto-detects prefix-style (`k__`, `d__`, etc.) vs positional format; maps to user-supplied `rank_system`. |
| `.crabs_std_hierarchy` | `R/fetch.R` | Character constant: standard 7-level CRABS/NCBI rank order used for positional taxonomy-string parsing. |

---

## Workflow Scripts

Six self-contained workflow scripts in `inst/workflows/`, replacing the old
monolithic `inst/TaxaLikely_workflow.R` (retained for reference but superseded).

| # | File | Purpose | Key functions |
|---|---|---|---|
| 1 | `1_fetch_references_workflow.R` | Build `reference_df` from NCBI or local FASTA | `fetch_reference_sequences()`, `read_reference_fasta()` |
| 2 | `2_flag_errors_workflow.R` | Find mislabeled references; explore/tabulate/report | `build_sequence_matrix()` → `flag_reference_errors()` |
| 3 | `3_train_model_workflow.R` | Train likelihood model from DNA reference matrix | `build_sequence_matrix()` → `train_likelihood_model()` → `interpret_model()` |
| 4 | `4_score_to_likelihood_workflow.R` | Convert match scores to likelihoods for TaxaAssign | `evaluate_likelihoods()` → `filter_top_hypotheses()` |
| 5 | `5_audit_coverage_workflow.R` | Audit reference completeness; constrain likelihoods | `infer_exclude_predicted()` → `audit_barcode_coverage()` / `audit_reference_coverage()` → `apply_coverage_constraints()` |
| 6 | `6_no_score_pathway_workflow.R` | No-score pathway: build uniform likelihoods from consensus assignments | `unreferenced_candidates()` → `assign_scores(score_type = "none")` |

**Layer-1 (Session 124-126), separate naming convention (`ecosystem_docs/LAYER1_WORKFLOWS.md`):**

| File | Purpose | Key functions |
|---|---|---|
| `image_acoustic_likelihood_workflow.R` | Image + acoustic score-to-likelihood, TWO independent live sections (not a DEBUG_MODE variant switch — both real, both run in the same tutorial session): Section 1 consumes TaxaMatch's real iNat CV checkpoint (`score_type = "similarity_softmax"`, unbounded raw score); Section 2 consumes TaxaMatch's real BirdNET checkpoint (`score_type = "probability"`, already 0-1 bounded). **Session 128:** both sections now open with `correct_training_bias()` (Section 2 first joins real Xeno-canto `n_recordings` via `audit_acoustic_coverage(xc_recordings = TRUE)`), plus a before/after honesty-check comparing corrected vs. uncorrected top-1 accuracy | `correct_training_bias()` → `unreferenced_candidates()` → `assign_scores()` |
| `sequence_likelihood_workflow.R` (Session 126) | Sequence/BLAST score-to-likelihood — the ONE Layer-1 data type needing the actual bivariate-normal self-vs-non-self model (no pre-trained classifier to calibrate). Consumes TaxaMatch's real `blast_sequences_workflow.R` checkpoint (5 real PtConception 12S queries) as the query side; fetches a real NCBI reference database live (6 genera / 3 fish families) as the training side. | `fetch_reference_sequences()` → `build_sequence_matrix()` → `calibrate_coverage_filter()` → `train_likelihood_model()` → `remove_flagged_references()` → `evaluate_likelihoods()` → `filter_top_hypotheses()` |

Workflows 2 and 3 share `build_sequence_matrix()` — build once, reuse.
Acoustic and image data use `unreferenced_candidates()` + `assign_scores()` (no training
step — classifiers are pre-trained; TaxaLikely acts as a post-classifier calibration layer).
Workflow 4 includes a one-liner to remove flagged errors from the match object
before evaluating likelihoods (no dedicated function needed).

### Other inst/ files

| File | Purpose |
|---|---|
| `inst/plot_likelihood_landscape.R` | Standalone two-panel visualization of H1/H2 density surfaces with example points (A/B/U). For presentations and manuscripts; not an exported function. |
| `inst/TaxaLikely_supplemental_methods.md` | Statistical methods background document adapted from early design docs; 10 sections covering the generative Bayesian framework, feature engineering, hypotheses, anchoring, and visualization. Future manuscript seed. |

---

## `model_params` Object (class `"taxa_model_params"`)

Output of `train_likelihood_model()`.

| Slot | Type | Description |
|---|---|---|
| `H1_Lookup` | data.frame | Per-species `lookup_key`, `rank`, `mu_score`, `mu_gap`, `sigma_score` (shrunk) |
| `H1_Global_Mu` | named numeric | Global fallback mean: `c(score_logit, gap_logit)`. |
| `H1_Sigma` | matrix | 2×2 global covariance over `(score_logit, gap_logit)`. |
| `H2` | list | Missing-species params: `delta` (logit offset from H1 mean), `sigma` (2×2). |
| `H3` | list | Missing-genus params: `delta`, `sigma` (2×2). |
| `Stats` | list | Diagnostics: `AIC_Score`, `n_species`, `n_singletons`, `n_anchors`. |
| `reference_errors` | data.frame | Output of `flag_reference_errors()` (mislabeled + singleton flags). Use with `remove_flagged_references()` to clean match objects. Auto-used by `run_bayesian_pipeline()`. |

---

## Critical Design Decisions (Session 31)

### rank_system convention
**Always coarse-to-fine** (e.g., `c("family", "genus", "species")`).
The last element (finest rank) maps to `rank_code_a` internally.
This matches the order of taxonomy columns in the match object.

### p_match scale
`build_sequence_matrix()` outputs `p_match = 1 - distance` where distance is
from DECIPHER (0-1 scale). All downstream functions (`flag_reference_errors()`,
`.prep_training_data()`) expect **p_match on 0-1 scale**.
The `score` column in the match object (input to `evaluate_likelihoods()`) can
be on either 0-1 or 0-100 scale -- `.normalize_scores()` auto-detects.

### H2/H3 sigma slots
`H2$sigma` and `H3$sigma` are **2×2 matrices** matching `H1_Sigma`. Dimnames:
`c("score_logit", "gap_logit")`.

### H2/H3 filtering
H2 and H3 hypotheses CAN be filtered out by `ratio_threshold` when scores
are high (the missing-taxon distribution is far from the observed scores).
This is correct behavior -- TaxaAssign treats absent rows as likelihood = 0.
Use `ratio_threshold = 0` to always retain all three hypothesis types.

### Rank generalization
`f_generalize_taxonomy_ranks()` from UBC is implemented inline in
`.prep_training_data()` as `.generalize_ranks()`. Not exported.
`f_ungeneralize_taxonomy_ranks()` from UBC is **dead code** -- never
used in the original source. Dropped entirely.

### TaxaTools::create_taxon_names() usage
Called inside `.evaluate_one_query()` to derive `taxon_name` + `taxon_name_rank`
for H2/H3 rows (where finest rank(s) are set to NA before calling).
Must be installed; it is in Imports.

---

## Test Coverage

All tests are fully offline (no NCBI, no DECIPHER, no external files) except `test-build.R`
which is skipped when DECIPHER/Biostrings are not installed.

| File | Functions covered | Notes |
|---|---|---|
| test-assign-scores.R | `assign_scores()` | Covers all score_type values including `"direct"`, H2/H3 anchoring, H4 behavior, single-H1 caveat |
| test-build.R | `build_sequence_matrix()` | Skipped when DECIPHER not installed (Bioconductor Suggests) |
| test-build-site-reference.R | `build_site_reference()` | Offline via `local_mocked_bindings()`; 17 tests + 1 skip (DECIPHER present) |
| test-clean.R | `remove_flagged_references()` | Fully offline |
| test-compute-likelihoods.R | `compute_likelihoods()`, `model_likelihoods()` | Fully offline with minimal model_params fixture |
| test-coverage.R | `audit_reference_coverage()`, `audit_acoustic_coverage()`, `apply_coverage_constraints()`, `calibrate_coverage_filter()`, `coverage_threshold()` | Fully offline |
| test-evaluate.R | `evaluate_likelihoods()`, `filter_top_hypotheses()` | Fully offline |
| test-expand-consensus.R | `expand_consensus_candidates()` (deprecated) | Fully offline; confirms deprecation warning fires |
| test-fetch.R | `read_reference_fasta()`, `.parse_taxonomy_tsv()`, `.parse_tax_string()` | Fully offline; NCBI fetch tests skipped |
| test-interpret.R | `interpret_model()` | Fully offline with minimal model_params fixture |
| test-normalize.R | `.normalize_scores()` | Fully offline |
| test-read-crabs.R | `read_crabs_output()`, `read_reference_fasta(taxonomy_file=)` | Fully offline; 16 + 7 tests |
| test-report_likelihood.R | `report_likelihood()` | Fully offline |
| test-subset-local-database.R | `subset_local_database()` | Fully offline; 25 tests; gz FASTA, pre-parsed taxonomy df, filters |
| test-train.R | `train_likelihood_model()`, `flag_reference_errors()` | Fully offline |
| test-unreferenced-candidates.R | `unreferenced_candidates()` | Fully offline |
| test-write-fasta.R | `write_reference_fasta()` | Fully offline |
| test-score-collapse.R | `detect_suppressed_candidates()`, `restore_suppressed_candidates()` | 24 test_that blocks; fully offline; covers all 3 rules, purity_threshold, perfect_threshold, no-score path |

---

## Statistical Design Notes

- **Score metric:** any raw match score; normalised to (0,1) then logit-transformed
- **Gap metric:** best-match logit score minus second-best logit score -- key discriminator
- **H1 (Known Species):** bivariate normal over `(score_logit, gap_logit)`.
  Species-specific score + gap means with Empirical Bayes shrinkage toward global mean.
- **H2 (Missing Species):** H1 distribution shifted left by `H2$delta` on score axis.
- **H3 (Missing Genus):** shifted further left by `H3$delta` = `H2$delta + 2.0`
- **Singleton queries:** 1D normal (score only) when only one candidate exists (gap uninformative).
- **Pseudo-data anchoring:** `anchor_perfect = TRUE` (default) injects synthetic
  perfect-match rows (score = logit(1-ε), gap = 95th percentile of real positive gaps)
  into training data. Prevents the "perfection penalty". Count = max(5, 10% of data).
- **Shrinkage:** `w = N / (N + prior_weight)`; per-species score variance + gap mean shrunk
  toward global. Default `prior_weight = 10.0`.
- **Per-species sigma floor (Session 121):** At inference, `use_sigma[1,1]` is floored at
  `global_sigma[1,1]` before evaluating H1 density. Species-specific sigma can be
  artificially tight for well-sampled species whose NCBI reference sequences are
  near-identical clones; tight sigma causes the Mahalanobis distance to balloon for
  realistic eDNA query scores, driving H1 likelihood near zero. The floor ensures the
  per-species distribution is never narrower than the global empirical distribution.
  Applied in `.evaluate_one_query()` after loading `sp_var` from `H1_Lookup`.
- **Score-only outlier filter, `alpha = 0.001` (Session 121):** Before computing H1
  density, `.evaluate_one_query()` tests whether the query score is consistent with the
  H1 species distribution via a univariate chi-squared test (df = 1, **score only**,
  not 2D bivariate). If `p_val < alpha`, H1 likelihood = 0. Gap excluded from this test:
  a small gap (confusable congener present) lowers the bivariate density correctly without
  spuriously rejecting the H1 candidate. Including gap in the outlier check rejected
  legitimate H1s in species-rich families (Leptocottus at 99% dropped because
  Agonomalus at 99% gave a tiny gap, inflating 2D chi-sq past threshold). Default alpha
  changed from `1e-6` → `0.001` (~3.3 sigma). Cyprinidae at 91–93% (>4 sigma from
  H1 mean, p < 0.001) drop; coastal species at 99% (~2.7 sigma, p ≈ 0.006) retained.
- **Monte Carlo:** n_sims perturbations of score_logit → `score_likelihood_mean` + `score_likelihood_sd`.
- **Median-across-references:** `evaluate_likelihoods()` takes the **median** score
  per taxon_name across multiple reference accessions before likelihood calculation.
- **Coverage filter (not a model dimension):** pass `min_coverage` to `evaluate_likelihoods()`
  to pre-filter candidates below an alignment/detection quality threshold. Use
  `calibrate_coverage_filter()` on the training matrix to find the Pareto-optimal threshold.

---

## Known Footguns

### trim_to_amplicon() rescued 0/107 over-length real Sebastes 12S sequences -- RESOLVED: not a trimming bug, but exposes that build_sequence_matrix()'s default length filter is too permissive for cross-source comparability (found + resolved manuscript-support session, 2026-07-07)
Live-fetched 238 real `Sebastes` (rockfish) 12S sequences from NCBI (`fetch_ncbi_reference_sequences(taxa = "Sebastes", barcode_term = "12S", max_per_species = 20L)`) while confirming a BayesianID_perspective manuscript claim outside this package (see `diagnostics/sebastes_chromis_confirmation.R`). 107 of 238 exceeded `max_len` (210bp) and were passed through `trim_to_amplicon(barcode_term = "MiFishU")` -- **0 of 107 were successfully trimmed**. The same 0%-rescue result then recurred on a second, unrelated genus (`Paralabrax`, kelp bass/sand bass): all 22 fetched sequences were ~415-600bp and 0/22 trimmed.

**Root cause, confirmed empirically (not a `trim_to_amplicon()` bug):** manually searched a real over-length `Paralabrax` sequence for both MiFish primers, both strands, allowing up to 6 mismatches (`Biostrings::matchPattern(..., max.mismatch = 6, fixed = "subject")`) -- **zero hits in any of the 4 combinations**. NCBI's `"12S"` free-text search term matches any GenBank record describing the 12S rRNA gene, not just MiFish-primer amplicons -- many real records (older Kocher-primer studies, broader mitochondrial fragments, etc.) cover a genomically different stretch of the same gene that never overlaps the MiFish binding sites at all. A 0% rescue rate is therefore correct behavior for these particular records, not a defect in the trimming logic. `trim_to_amplicon()`'s own synthetic test fixtures (Sessions 140-142) all embed a matchable primer site by construction, so this "real record has no primer site to find" case was never exercised until now.

**The more consequential, broadly-actionable finding:** `build_sequence_matrix()`'s default `min_seq_len = 100L, max_seq_len = 2000L` is wide enough that it does **not** filter out these off-target, non-MiFish-window sequences -- they pass straight into alignment and pairwise-distance calculation alongside genuine short MiFish-amplicon sequences. For `Sebastes`, this went unnoticed at first because DECIPHER's alignment coincidentally produced high divergence (and thus exclusion via the `distance < 0.25` pair-retention step) for most such cross-window pairs -- but for `Paralabrax`, ALL fetched sequences were off-target long fragments, so the *entire* resulting seq_matrix was built from a different genomic window than intended, silently invalidating a same-species vs. congeneric %-match comparison that looked superficially normal (non-empty, plausible-looking output). This would not have been caught without an independent, methodologically-motivated reason to compare two genera against each other and notice the numbers looked inconsistent.

**How to apply:** when reference sequences are fetched by a broad NCBI text search term (e.g. `barcode_term = "12S"`) rather than sourced from a curated amplicon-only database, do not trust `build_sequence_matrix()`'s default length filter to guarantee amplicon-window comparability across taxa/sources -- it only guards against absurdly short/long sequences, not "same region as every other sequence in this matrix." Explicitly filter `reference_df` to the registered amplicon length range first (`TaxaTools::resolve_barcode_lengths("MiFishU")` gives `130-210`bp for MiFish-U/E) before calling `build_sequence_matrix()`, especially when comparing results *across* separately-fetched taxon sets rather than just running one self-contained pipeline. See `diagnostics/sebastes_chromis_confirmation.R` for the corrected pattern.

### .xc_recording_count() required v2 -> v3 migration (found Session 124, FIXED Session 125)
`.xc_recording_count()` (`R/coverage.R`), used by
`audit_acoustic_coverage(xc_recordings = TRUE)`, called the dead
`https://xeno-canto.org/api/2/recordings` endpoint (404 unconditionally as of
Session 124's Xeno-canto migration). Because it checked `resp_status(resp) != 200L`
and returned `NA_integer_` on any non-200, the failure was **silent** -- the same
"silently degrades instead of erroring" pattern as the `.resolve_llm_fn()` footgun in
`TaxaID/CLAUDE.md`. Fixed Session 125: switched to
`https://xeno-canto.org/api/3/recordings`, added a required `key` query param read from
the `XC_API_KEY` environment variable (register at xeno-canto.org/explore/api; set via
`~/.Renviron`), and rewrote the query from v2's free-text to v3's tag-based syntax
(`gen:{genus} sp:{species} type:call`). If `XC_API_KEY` is unset, the function now warns
explicitly and returns `NA_integer_` (no longer silent). Live-verified against 4 real
species (`Turdus migratorius`, `Setophaga petechia`, `Limosa fedoa`,
`Selasphorus calliope`) via both `.xc_recording_count()` directly and
`audit_acoustic_coverage(xc_recordings = TRUE)` end-to-end -- all returned real,
non-NA counts.

### TaxaTools::create_taxon_names() must be installed
`evaluate_likelihoods()` calls `TaxaTools::create_taxon_names()`. If TaxaTools
is not installed (e.g., in test environments), tests that call `evaluate_likelihoods()`
will fail. Guard with `skip_if_not_installed("TaxaTools")`.

### build_sequence_matrix() needs DECIPHER + Biostrings (Suggests)
These are Bioconductor packages. Install with `BiocManager::install("DECIPHER")`.
They are in Suggests, not Imports -- not loaded at package startup.
The function checks for them at runtime.

### lme4 hierarchy fitting with small data
`train_likelihood_model(use_hierarchy = TRUE)` requires enough taxonomic levels
(>= 2 rank columns in training data) and sufficient variance across ranks for
lme4 to converge. Falls back gracefully to global mean with a message.

### Single H2/H3 anchor — non-best genera get no unreferenced hypothesis
`.evaluate_one_query()` generates exactly one H2 row (unreferenced species in the
best candidate's genus) and one H3 row (unreferenced genus in the best candidate's
family), both anchored at the single globally best-scoring candidate. This is
intentional: when one genus clearly dominates, its unreferenced congeners are the
relevant alternative hypotheses, and the gap feature already signals ambiguity when
genera are nearly tied. The implicit assumption is that near-tied multi-genus
observations are routed through the consensus/upranking pathway (uniform likelihoods)
rather than `evaluate_likelihoods()`. Known limitation: near-tied multi-genus queries
that bypass upranking will not receive unreferenced hypotheses for the non-best genus.

### expand_unreferenced_hypotheses() workflow order
`expand_unreferenced_hypotheses()` must run **before** `apply_coverage_constraints()`.
Coverage constraints operate on `hypothesis_type` and `taxon_name`; if constraints are
applied first (zeroing the generic H2 row), expansion will produce named rows with
non-zero likelihoods that bypass the constraint. Correct order:
`evaluate_likelihoods()` → `filter_top_hypotheses()` → `expand_unreferenced_hypotheses()`
→ `apply_coverage_constraints()`.

---

## Session Notes

**Session 142 (2026-07-06): trim_to_amplicon() now supports the real eDNA COI mini-barcode (coi-leray)**

Direct same-day follow-on to Session 141, which explicitly flagged the Leray et al.
(2013) mini-barcode (mlCOIintF/jgHCO2198, the actual ~313bp fragment most real COI
metabarcoding studies use -- not `coi-folmer`'s full-length ~710bp Sanger-era product)
as unimplemented, blocked by Geller et al. (2013)'s `jgHCO2198` reverse primer using
inosine (dITP), a base analog `Biostrings::DNAString` has no representation for. The
user asked to learn more about the mini-barcode's discriminatory-power tradeoffs before
deciding whether to invest in solving that.

**No code change needed in this package again** -- all the work was in
`TaxaTools::barcode_primer_defaults` gaining a `coi-leray` entry (pairs Leray's own
inosine-free forward primer with Meyer (2003)'s inosine-free degenerate reverse primer
`dgHCO2198` instead of Geller's, a real published pairing, not an invented workaround --
see `TaxaTools/CLAUDE.md`'s own Session 142 note for the full verification record and
the discriminatory-power literature summary). `trim_to_amplicon(barcode_term =
"COI-Leray")` resolves through the same already-generic path as every other marker.

New test confirms `trim_to_amplicon()` correctly extracts a real, literature-verified
Leray-fragment amplicon from a synthetic over-length sequence (same fixture pattern as
the Session 141 markers); one existing test that had assumed bare `"COI"` resolved
uniquely (updated to `"COI-Folmer"` explicitly, since `"COI"` alone is now ambiguous
between `coi-folmer` and `coi-leray` -- confirmed by a new test that this errors rather
than silently picking one). `devtools::test()` (58/58 in `test-trim-to-amplicon.R`;
full suite 609 passing, up from 605, 0 failures, same 15 pre-existing unrelated
warnings) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.

**Still not implemented**: the more-degenerate "Leray-XT" mlCOIintF variant (partially
mitigates, but doesn't eliminate, the primer-mismatch-driven non-amplification in
certain marine zooplankton taxa noted in the discriminatory-power review); any
vertebrate-tolerant COI primer pair (Folmer's own known limitation, noted Session 141,
remains unaddressed); wiring `trim_to_amplicon()` into any production workflow script.

**Session 141 (2026-07-06): trim_to_amplicon() now covers every mito/chloroplast marker, not just MiFish-12S**

Same-day follow-on to Session 140. The user asked two things directly: (1) is
primer-based trimming actually worth it for 12S, or better to just drop over-length
sequences? (2) work through the rest of the mitochondrial and chloroplast markers in
`TaxaTools::barcode_length_defaults` (nuclear genes -- 18S, ITS, ITS2 -- explicitly
excluded per the user's own instruction, since none of them has one canonical primer
pair to verify the way every mito/chloroplast marker does).

**Opinion on 12S**: yes, practical -- the fallback is always exactly today's
length-exclusion behavior (this function can only rescue sequences that would
otherwise be lost, never discard ones that would otherwise be kept), the primer
specificity plus length-plausibility gate make a spurious accept astronomically
unlikely, and the problem is already observed on real data (Session 139's "No H1
pairs found" bug).

**No code changes needed in this package.** `trim_to_amplicon()` was already fully
generic over `barcode_term` -- all the new-marker work happened in
`TaxaTools::barcode_primer_defaults`, which gained 6 new entries (16S, COI, cytb,
rbcL, matK, trnL), each verified against 2-3 independent literature sources AND
empirically tested with `Biostrings::matchPattern()` against a real GenBank
mitogenome or chloroplast genome fetched live via NCBI eutils -- not just trusted from
citation text. This caught two real errors a literature-only check would have missed
(a wrong cytb amplicon length repeated by two secondary sources -- corrected from a
mistaken 309bp to the empirically-measured 358bp -- and a genuine forward/reverse
mislabeling in an otherwise-authoritative matK primer table, resolved by testing both
orientations directly against real chloroplast DNA). Full verification record is in
`TaxaTools/CLAUDE.md`'s own Session 141 note.

Added 21 new offline tests here confirming the *consuming* side works correctly with
the newly-registered primers: real COI-Folmer and rbcLa pairs each correctly extract
from a synthetic over-length sequence built around them, plus a loop test exercising
all 6 new registry entries end-to-end through `trim_to_amplicon()` itself (not just
through the registry lookup, which `TaxaTools`'s own tests already cover). One
existing test's example marker changed from `"COI"` (now registered, so no longer a
valid "unregistered marker" example) to `"ITS2"`.

`devtools::test()` (54/54 in `test-trim-to-amplicon.R`; full suite 605 passing, up
from 588, 0 failures, same 15 pre-existing unrelated warnings) + `devtools::check()`
(0 errors, 0 warnings, 0 notes) all clean.

**Still deliberately unimplemented**: 18S/ITS/ITS2 primer entries (no canonical pair
to verify); wiring `trim_to_amplicon()` into any production workflow script (still
the case from Session 140); the Geller et al. (2013) jgLCO1490/jgHCO2198 redesigned
COI primers, which use inosine (`I`) -- not a standard IUPAC symbol
`Biostrings::DNAString` supports, so they can't be implemented with the current
algorithm without a lossy `N`-substitution approximation that wasn't attempted this
session; and the Leray et al. (2013) mlCOIintF/jgHCO2198 mini-barcode ("Leray
fragment"), the actual eDNA-relevant COI marker, blocked by the same inosine issue on
its reverse primer.

**Session 140 (2026-07-06): trim_to_amplicon() -- in-silico PCR amplicon extraction, implements the Session 139 reentry design doc**

Implements `ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md`
in full. That doc deliberately stopped short of recommending answers to its own open
design questions (package placement, primer scope, naming) -- resolved with the user at
the start of this session before writing any code:

- **Package placement** (design question 4): user pushed back on the doc's own
  TaxaLikely recommendation, asking for the TaxaMatch/TaxaFetch alternatives to be
  argued through rather than assumed. Worked through it explicitly: TaxaFetch only ever
  handles *occurrence* data (GBIF/DataONE), never reference sequences, so it doesn't
  fit despite the name. TaxaMatch has the raw-sequence/`Biostrings` tooling but is
  strictly query-side (`TaxaMatch → TaxaLikely`, one direction) -- putting a
  reference-database-shaping function there would either reverse that dependency
  direction or split one pipeline stage across a package boundary. TaxaLikely already
  owns the entire reference-fetch/reference-QC pipeline this slots into
  (`fetch_ncbi_reference_sequences()`, `read_reference_fasta()`,
  `build_sequence_matrix()`, `audit_barcode_coverage()`) with no new cross-package
  dependency either way. User confirmed TaxaLikely on that reasoning.
- **Primer scope** (design question 1): user's own framing was that the package should
  stay generic to marker type, populate the registry only where the "long submission
  contaminates the short-barcode training set" problem is real and a primer pair can be
  verified, and have a fallback plan (point users at CRABS pre-trimming, and confirm a
  length-based exclusion filter already exists) if broader coverage turns out to be too
  much work. Landed on: `trim_to_amplicon()` itself is fully generic (any primer pair
  via `primer_fwd`/`primer_rev` works, registry lookup via `barcode_term` is a
  convenience, not a requirement); the registry itself is populated only with MiFish-U/E
  (12S) this session -- the only marker with real production use in this ecosystem
  (confirmed by grep: every real `barcode_term` ever passed by a live workflow is
  `"MiFishU"`) and a single, well-established, verifiable primer pair. Confirmed the
  fallback length filter already exists and needed no new work:
  `build_sequence_matrix()`'s existing `min_seq_len`/`max_seq_len` step (`R/build_sequence.R`,
  "LENGTH FILTER" section) already excludes anything `trim_to_amplicon()` can't rescue,
  exactly as before this session -- this function only ever adds sequences that would
  otherwise be lost, never removes ones that would otherwise be kept. 18S was
  deliberately NOT given a registry entry: unlike MiFish, there is no single canonical
  18S primer pair (the existing `barcode_length_defaults` comment already flags "varies
  widely by primer set") -- inventing one would be exactly the unverified-citation risk
  the reentry doc warned against. 18S callers must supply `primer_fwd`/`primer_rev`
  directly from their own wet-lab protocol, or pre-trim with CRABS.
- **Naming** (design question 4b): `trim_to_amplicon()` / `barcode_primer_defaults`,
  user's direct choice over the doc's `extract_amplicon()` alternative.

**Primer sequences verified, not trusted from memory.** Per the reentry doc's explicit
instruction ("citing real primer papers... is real work, not a placeholder task"), used
live web search to cross-check the MiFish-U/E sequences against Miya et al. (2015)'s own
primary text plus two independent secondary sources (a university core-facility protocol
page, a GitHub pipeline's README) before adding them to
`TaxaTools::barcode_primer_defaults` -- all three agreed verbatim:
MiFish-U-F `GTCGGTAAAACTCGTGCCAGC` / MiFish-U-R `CATAGTGGGGTATCTAATCCCAGTTTG`
(amplicon 163-185bp); MiFish-E-F `GTTGGTAAATCTCGTGCCAGC` / MiFish-E-R
`CATAGTGGGGTATCTAATCCTAGTTTG` (amplicon 170-185bp). New
`TaxaTools::resolve_barcode_primers()` deliberately does *not* mirror
`resolve_barcode_lengths()`'s substring-prefix convenience matching for a bare
`"mifish"` -- U and E have genuinely different primer sequences, so an ambiguous term
errors with guidance instead of silently picking one (see `TaxaTools/CLAUDE.md`'s own
Session 140 note).

**Algorithm choices empirically verified via real `Biostrings` calls before being
written into the function**, not assumed from documentation alone: confirmed
`Biostrings::matchPattern(fixed = FALSE)` produces spurious matches across long
N-runs (ambiguity codes in the *subject* matching every primer base for free), and that
`fixed = "subject"` (the reentry doc's own suggested value) correctly avoids this while
still letting a degenerate primer base match a literal subject base -- reproduced both
behaviors directly in a throwaway script before committing to the design. Also
empirically confirmed the both-strand search (via `Biostrings::reverseComplement()`)
correctly recovers a primer pair when a sequence was deposited on the opposite strand,
and that `max.mismatch` tolerates a real single-base substitution at a primer-binding
site. `Biostrings::start()`/`end()` must be called via explicit `::` (a bare `start()`
resolves to base R's own S3 generic and silently returns wrong values for an
`XStringViews` object) -- caught by testing this directly rather than assuming.

**Implausible-span guard**: an extracted "amplicon" is only accepted if its span falls
within `[min_len, max_len]` (from `barcode_length_defaults` via `barcode_term`, or
supplied directly) -- without this, a spurious far-apart primer pairing inside a large
sequence could produce a near-original-length "amplicon" that passes through
undetected. Caught by an early test failure during development (a deliberately
long-interior synthetic fixture) before it could reach real data.

37 new offline tests (`test-trim-to-amplicon.R`), all using real, verified MiFish-U
primer sequences embedded in synthetic flanking contexts rather than fabricated
primers -- covers: already-short sequences left untouched; correct extraction on the
sense strand; correct extraction when the sequence was deposited on the antisense
strand; single-base-mismatch tolerance and its rejection at `max_mismatch_rate = 0`;
graceful fallback when a primer is genuinely absent; the implausible-span rejection;
explicit `primer_fwd`/`primer_rev` bypassing the registry; mixed-outcome multi-row
input; and non-IUPAC (protein-looking) sequences flagged rather than crashing. Plus 8
new offline tests for `TaxaTools::resolve_barcode_primers()`
(`test-barcode_utils.R`) covering exact/case/separator-insensitive matching, the
MiFish-U vs. MiFish-E distinction, the deliberate ambiguous-bare-term error, and input
validation.

Live-verified end to end against a realistic simulated 16kb mitogenome (random-sequence
flanks, not a repeated motif, to avoid an artificially easy case) containing a real
embedded MiFish-U amplicon: correctly extracted exactly 172bp -- matching Miya et al.
2015's own reported mean MiFish-U amplicon length -- while a co-occurring
already-short, already-primer-trimmed barcode submission (the common real deposition
convention) was correctly left untouched. This is the exact scenario that broke
`train_likelihood_model()` in Session 139 ("No H1 pairs found"), now rescuable instead
of being discarded outright.

`devtools::document()` + `devtools::test()` (TaxaTools: 77/77 in `test-barcode_utils.R`,
full suite unaffected; TaxaLikely: 37/37 in `test-trim-to-amplicon.R`, full suite 588
passing / 0 failures / 15 pre-existing unrelated warnings) + `devtools::check()` on both
packages (0 errors, 0 warnings, 0 notes) all clean.

**Not done / deliberately deferred**: no other marker besides MiFish-U/E was added to
`barcode_primer_defaults` -- 18S in particular was explicitly ruled out this session (no
single canonical primer set exists to verify); `trim_to_amplicon()` is not wired into
any of the four production `PtConceptionWorkflow_*`/`MuguFishWorkflow.R` scripts or the
Layer-1 `sequence_likelihood_workflow.R` -- those still use the length-exclusion-only
fix from Session 139's sibling GBIF reentry doc. BLAST-alignment-coordinate trimming
(the reentry doc's "ruled out as a shortcut" alternative) remains unimplemented and
unrevisited.

**Session 136 (2026-07-05): fetch_reference_sequences() renamed; real PR2 support added; BOLD wrapper work blocked by a live outage**

Follow-on from Session 135's `ecosystem_docs/EXTERNAL_DATA_SOURCES.md` work: reviewing
that table with the user identified BOLD Systems and PR2 as worth real engineering
investment (Macaulay Library explicitly dropped as too access-gated/legally risky).

**Rename**: `fetch_reference_sequences()` → `fetch_ncbi_reference_sequences()`. The old
name didn't say NCBI anywhere, which stopped being safe once a second live-API
reference source (BOLD) was on the table. Old name kept as a pure forwarding deprecated
alias (`.Deprecated()`, `@rdname` folding into the same Rd page), mirroring
`audit_barcode_coverage_ncbi()`'s existing pattern exactly. All internal call sites
updated to the new name directly: `build_site_reference()`, both `1_fetch_references_workflow.R`
and `sequence_likelihood_workflow.R`, `README.md`, and (cross-package)
`TaxaWizard`'s `taxa_to_refs.R`/`taxa_to_site_refs.R` snippets. The
`test-build-site-reference.R` mock bindings were also updated to target the new name —
missing this would have made the mocks silently stop intercepting, since
`local_mocked_bindings()` replaces by exact name.

**Real PR2 support** (`subset_local_database()`/`.parse_tax_string()`): downloaded a real
PR2 v5.1.1 release file (`pr2_version_5.1.1_SSU_mothur.tax.gz`, 240,201 records — the
smallest real release asset, not the multi-GB FASTA) to check PR2's actual taxonomy
string format directly rather than assume compatibility, per the plan's explicit
"verify before writing code" instruction. Confirmed PR2 uses a **fixed, always-9-level
positional format** (`domain;supergroup;division;subdivision;class;order;family;genus;species`,
100% uniform across all 240,201 records, no prefix codes) that does not match
`.crabs_std_hierarchy`'s 7-level kingdom-first shape either in count or rank names.
Added `.pr2_hierarchy` as its own constant and made `.parse_tax_string()`'s positional
branch dispatch on field count (exactly 9 → PR2; otherwise → the existing 7-level
constant) — a real, verified structural signal, not a heuristic guess. Two additional
real quirks found and deliberately preserved rather than "cleaned": plastid-derived
sequences suffix every taxonomic level with `:plas` (e.g. `Eukaryota:plas`) — collapsing
this would erase a real, scientifically meaningful ancestry distinction, so it's kept
as-is in the parsed value; and PR2's `species`-level values are underscore-joined and
often unresolved placeholder labels (e.g. `Rozellomycota_XXX_sp.`) rather than clean
binomials, left for callers to post-process if needed. Live-verified `.parse_tax_string()`
against the real 9-level, `:plas`-tagged, 7-level (MIDORI2), and prefix-style (SILVA/GTDB)
cases side by side to confirm no regression. 4 new offline tests added to
`test-subset-local-database.R` using the real downloaded strings verbatim (not
fabricated), all passing (37/37 in that file, 0 regressions).

**MIDORI2 license caveat**: added to `subset_local_database()`'s `@section Supported
database formats` — MIDORI2's license is reported as CC-BY-NC in secondary sources
(unconfirmed on the primary site, per `EXTERNAL_DATA_SOURCES.md`'s MIDORI2 row),
potentially in tension with this ecosystem's CC0/USGS public-domain policy. Flagged as
needing resolution before redistributing any cached MIDORI2-derived data. Documentation
only, no code change.

**BOLD: not an outage — a full API migration. Real API found, `fetch_bold_reference_sequences()`
built and shipped.** First diagnosis this session (see below) was wrong in framing, not
in observation: installed `bold` (ropensci/bold, archived from CRAN 2024-08-26) via
`remotes::install_github()` to live-verify its output before writing any reshape code,
per this session's "verify, don't guess" discipline, and both `bold_seqspec()` (returns
an HTML "BOLD Public Offline" page) and `bold_identify()` (crashes on non-XML content)
failed live. When the user reported BOLD's website looked up and asked to recheck,
further digging found the real cause: **BOLD migrated to an entirely new "v5" API in
2024; the old v3/v4 endpoints the `bold` package targets are permanently retired, not
temporarily down.** Found and fully live-tested the real replacement: BOLD's v5 Data
Portal API (`portal.boldsystems.org/api`), documented by its own public OpenAPI spec
(`portal.boldsystems.org/openapi.json`). Confirmed the complete 3-stage flow live
end-to-end (`query/preprocessor` → `query` → `documents/{id}/download`), and pulled the
real field list directly from live records rather than secondhand docs.

**Built `fetch_bold_reference_sequences()` directly against this API via `httr2`** (see
Function Inventory above) — no `bold` package dependency needed at all, sidestepping the
whole archived-from-CRAN dependency question. Live end-to-end test (`Fundulus` +
`Danaus plexippus`): 103 real sequences, 38 species, 84% real coordinate coverage
(87/103) — notably better location coverage than NCBI/GenBank typically has. Found and
fixed one real bug this way: different taxa return different column sets from BOLD's
TSV export, so combining needed `dplyr::bind_rows()`, not `rbind()` (which errors on
mismatched columns).

**Query/ID-engine side (`identify_bold_sequences()`, TaxaMatch) — investigated,
no public API found, not built.** Pulled BOLD's complete OpenAPI paths list (20
endpoints, all reference/query-by-known-criteria) and confirmed no
identification/sequence-matching endpoint exists anywhere in it. BOLD's "Barcode ID"
tool now lives at `id.boldsystems.org` and every page checked describes only a
web-form (paste/upload sequence, click Identify), no documented REST endpoint. This may
be a real, permanent capability gap under BOLD v5, not an oversight — see
`project_bold_v5_migration_resolved` memory for the full record and how to re-check if
BOLD ever publishes one.

`devtools::document()` + `devtools::test()` (551 passing, 0 regressions) +
`devtools::check()` (0 errors/warnings/notes) all clean for the rename, PR2, and BOLD
reference-fetch work.

**Session 135 (2026-07-05): GenBank + Xeno-canto location extraction — closes two of three gaps in `ecosystem_docs/TODO_validation_benchmark.md`'s "Sourcing location data" section**

Scoped narrowly to the location-metadata plumbing itself, not the leave-one-out
benchmark harness (still gated behind the user's 2026-07-04 directive — confirmed
explicitly out of scope this session before starting).

**GenBank side** (`R/fetch.R`): confirmed directly that neither
`.fetch_summaries_batched()` (ESummary: `acc`/`title`/`taxid`/`slen`/`organism`) nor
`.fetch_taxonomy_map()` (taxonomy DB: lineage only) ever retrieves a record that can
carry `/lat_lon` or `/country` — those live only in the full GenBank nucleotide record's
`source` feature qualifiers. Added `.parse_lat_lon()` (pure INSDC `lat_lon` string
parser, e.g. `"36.789 N 121.947 W"` → signed decimal `c(lat=, lon=)`; degrades to
`NA`/`NA` on anything unparseable rather than erroring, since GenBank free-text is
inconsistent) and `.fetch_locations_batched()` (batched `rentrez::entrez_fetch(db =
"nucleotide", rettype = "gb", retmode = "xml")`, passing accessions directly as `id` —
the same convention `.fetch_fasta_batched()` already uses successfully, so no separate
search→summary round trip is needed). `fetch_reference_sequences(include_location =
FALSE)` — new opt-in trailing param; when `TRUE`, joins `lat`/`lon`/`country` onto the
final `reference_df` by `composite_id`.

**Xeno-canto side** (`R/coverage.R`): `.xc_recording_count()` was already performing the
exact HTTP request whose response body contains a `recordings` array with `lat`/`lng`
per recording — it just read `numRecordings` and threw the rest away. Extracted the
shared HTTP call into `.xc_recordings_raw()` and rewrote `.xc_recording_count()` to call
it (zero behavior change, confirmed by keeping its call sites' existing tests passing
unmodified plus a new direct test). Added `.xc_recording_locations()` (per-recording
`species`/`xc_id`/`lat`/`lon`/`country` — XC's `lat`/`lng`/`cnt` fields are already plain
decimal-degree/text strings, no DMS parsing needed unlike GenBank) and exported
`fetch_xc_recording_locations()` as the public entry point (1s/species rate limit,
matching `audit_acoustic_coverage()`'s own). `xc_id` is XC's own catalog number, not a
`build_site_table()`-ready `observation_id` — deliberately left for the caller to map to
their own BirdNET observation-id convention.

BOLD's equivalent location fields remain unchecked (separate TBD, no BOLD integration
exists anywhere in the ecosystem) and wiring either of the above into an actual
`TaxaMatch::build_site_table()` `site_df` call is left for benchmark-harness time, once
a real caller exists — both explicitly out of scope this session.

New tests: `.parse_lat_lon()` (6 cases, `test-fetch.R`), `.fetch_locations_batched()`
empty-input typing (`test-fetch.R`), `.xc_recording_count()`/`.xc_recording_locations()`/
`fetch_xc_recording_locations()` via `local_mocked_bindings()` on `.xc_recordings_raw()`
(`test-coverage.R`), matching the offline-mock convention already used in
`test-build-site-reference.R`. No live NCBI/Xeno-canto network calls added to the test
suite. `devtools::document()` + `devtools::test()` (512 expectations, 0 failures, 15
pre-existing unrelated warnings) + `devtools::check()` (0 errors, 0 warnings, 0 notes)
all clean.

**Session 133 (2026-07-03): acoustic tau re-calibrated on a broad, multi-cluster real dataset — Session 128/129's tau≈1 for acoustic does NOT hold; pooled result is tau≈0, matching image, but per-cluster results are genuinely heterogeneous**

Session 129's acoustic number (`tau ≈ 1` helps, later re-confirmed by log-loss at
`tau ≈ 3.6`) rested on 3 species, all one genus (*Calidris*), 9 recordings, 42 detection
windows — flagged by the user as too thin an evidence base to trust as a general
default. This session redid the calibration on a deliberately-designed, real,
much larger dataset: **8 confusable clusters, 24 species, 191 real Xeno-canto
recordings, real BirdNET-Analyzer runs, 2487 detection windows** (up from 42). Full
design rationale, live Xeno-canto recon, species list, and reproducible method detail
are in `ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md` (now marked
complete) — this note summarizes the result.

**Design, briefly:** clusters chosen from real, live-verified Xeno-canto `n_recordings`
counts, not guessed — an initial assumption that confusable congener pairs would show
orders-of-magnitude count contrast was wrong; real confusable pairs mostly span only
2-7x. One genuine outlier was found and included (*Phylloscopus collybita* vs.
*ibericus*, ~19x — a species pair only recently split, still essentially inseparable by
song). A low-confusability control cluster (*Turdus migratorius* vs. *Megascops asio*)
was included specifically to test whether `tau` does damage where there's nothing to
correct. The original 3 Calidris species were folded back in at the same sampling depth
as everything else, so this result supersedes rather than discards Session 128/129's
pilot.

**Pooled result: `tau ≈ 0` is optimal — log-loss and accuracy both get monotonically
worse from `tau = 0` (log-loss 4.4136, 71% accuracy, 1771/2487) through `tau = 6`
(log-loss 4.6200, 68%).** This reverses Session 129's acoustic finding and now agrees
with image's own `tau ≈ 0` result — the "image and acoustic need opposite corrections"
conclusion from Session 129 does not survive a properly powered sample.

**Per-cluster breakdown (new diagnostic, not run in any prior session) shows this is
not uniform, though:** 5 of 8 clusters (Catharus, Control, Empidonax, Melospiza,
Chiffchaff — collectively ~1900 of 2487 windows) independently favor `tau` at or near 0,
which is why the pooled fit does too. But **Calidris (152 windows) and Woodpecker
(172 windows) both still prefer high `tau` (5.0 and 6.0 respectively) even at this much
larger scale**, and both optima are pinned at the swept grid's edge (`tau = 6`),
meaning their true optima are still unbracketed. Accipiter also "prefers" `tau = 6`, but
that cluster's accuracy is poor (41%) regardless of `tau` (59% complete-miss rate — the
true species frequently isn't even among BirdNET's candidates at all, a coverage
problem no amount of re-weighting fixes), so its tau=6 result is not treated as
meaningful signal, just noise on a bad cluster. **Practical conclusion: a single global
`tau` does not fit this data well — it behaves as if it should be cluster/taxon-specific
rather than one ecosystem-wide scalar.** That's a new open design question, not resolved
this session.

**True=rare vs. true=common balance check (new diagnostic):** among 211 windows where
the top-2 candidates' `n_recordings` differed by ≥1.5x, the TRUE species was the more
*common* candidate 44% of the time (93/211) vs. the rarer candidate only 18% of the time
(37/211) — the remainder (38%) matched neither top-2 candidate. This directly explains
why a large `tau` loses on the pooled fit: favoring the rarer candidate is wrong more
often than it's right in this broader, more representative sample — the opposite of
what the narrow Calidris pilot implied. This was exactly the design concern flagged
before data collection (an all-true=rare sample would make large `tau` trivially win by
construction); good to have it checked and refuted rather than assumed away.

**One real, confirmed bug found and fixed while building the dataset:** Xeno-canto
tags Hairy Woodpecker as `Leuconotopicus villosus` (its older genus), but BirdNET's own
internal taxonomy calls it `Dryobates villosus` and never once output the XC-tag name —
confirmed directly (0/8 Hairy Woodpecker files matched `Leuconotopicus villosus`; 126
rows matched `Dryobates villosus`). Every Hairy Woodpecker window was silently
registering as a complete miss even where BirdNET correctly identified the bird. Fixed
by correcting the true-species label to match BirdNET's own taxonomy (not by re-fetching
audio — the XC tag is still the correct thing to query by; only the ground-truth label
used for scoring needed to change). Woodpecker's accuracy went from 22% to 88% after the
fix. Checked all other 23 species for the same failure mode (does BirdNET ever output
that species' own name for its own recordings, at all) — none had it; this looks like a
one-off Xeno-canto/BirdNET taxonomy divergence for this specific species, not a
systemic issue. Worth checking for any future species added to this kind of design,
though — it's the second live taxonomy-tag mismatch found on Xeno-canto data this
session (the other, `Dryobates villosus` returning 0 hits on Xeno-canto's own search
API, was caught during species selection, before any data was pulled).

**Net effect on the package:** **there is currently no real-data evidence supporting
`tau > 0` as a general default for either data type (image or acoustic).** The
package's own default remains `tau = 1.0` (Menon et al. 2020's theoretical
Fisher-consistent value) — this session's result doesn't prove `tau = 1.0` is wrong in
principle, only that it hasn't been empirically supported yet on any real dataset built
so far, image or acoustic. Whether `correct_training_bias()` should ship with a
different default, or a per-context `tau`, remains an open decision — not changed this
session (would need to touch multiple files/tests; flagging for a deliberate choice
rather than making it unilaterally here).

Not done: bracketing Calidris/Woodpecker's true per-cluster optima (grid capped at
`tau = 6`, both still climbing); wiring any of this into
`TaxaAssign::camera_trap_posterior_workflow.R` (still uses the old `tau = 1.0` default);
whether `.xc_recording_count()`'s `type:call`-only restriction is even the right
training-representation proxy (flagged, not investigated).

**Session 129 (2026-07-03): assign_scores() score-scale bug found and fixed; tau/score_sharpness jointly calibrated on clean data — image result resolved, superseding Session 128's number**

Expanded the Session 128 image photo set from 6 to 52 real photos (8 species, 3 new:
raccoon, California ground squirrel, Virginia opossum) to get past a small-n result.
Two real, previously-hidden bugs surfaced while doing this, both now fixed:

1. **iNaturalist returns off-scope candidates** (plants, birds) that a mammal-only camera-
   trap study can never actually be. `TaxaMatch::score_image_workflow.R` now filters to
   `iconic_taxon_name == "Mammalia"` right after scoring, before any downstream step can
   assign the impossible candidates probability mass. Real examples removed: *Baccharis
   pilularis* ("coyote brush", a plant) for coyote.JPG, *Megascops kennicottii* (a screech
   owl) for rabbit.JPG — the second of these is the exact taxon Session 128's flip report
   named, meaning that specific result was already partly a scope-filter artifact, not a
   pure `tau` effect.

2. **`assign_scores()`'s `similarity_softmax` path collapsed to near-uniform likelihoods**,
   independent of `tau` entirely. `.normalize_scores()` forced iNaturalist's unbounded
   `combined_score` (real data reaches ~3000) through a fixed 0-100 divisor meant for
   BLAST-style percent-identity scores; every candidate in every photo ended up with
   `score_likelihood` within ~0.1% of 1.0 regardless of which one iNat actually favored.
   Confirmed directly: a tau-only sweep on 51 scope-filtered photos showed log-loss
   essentially FLAT across the entire `tau` range (2.4624 to 2.4638, 0.05% relative) while
   accuracy swung 22 points non-monotonically — the two metrics disagreeing that sharply
   was the tell that something other than `tau` was driving accuracy, and a per-photo
   probability trace confirmed it (every candidate ~0.999-1.000, an almost perfectly
   uniform distribution).

**Fix** (`R/assign_scores.R`): score scale is now auto-detected once per call from the
global max of `score_col` across all `specific_candidate` rows — no new caller-facing
parameter, so every data type (existing and future) is handled without per-type
configuration. `max <= 100` (BLAST/percent-identity): unchanged fixed-divisor behavior,
confirmed byte-for-byte identical via the full existing test suite (497 expectations, 0
failures) and a targeted synthetic check. `max > 100` (iNaturalist `combined_score`, or
any other genuinely unbounded score): each observation is normalized against its own
candidate range instead, restoring real discrimination (synthetic check: spread went from
~0.001 to ~0.095 between best and worst candidate).

**Joint (tau, score_sharpness) calibration on clean data** (`TaxaLikely/inst/workflows/
calibrate_training_bias_tau.R`, extended from a tau-only sweep after finding
`score_sharpness = 0.1`'s default is also poorly matched to this data type — a 2D grid,
72 combinations, log-loss-minimizing, refined with `stats::optim()`): on the 51 real,
scope-filtered, correctly-scaled photos, log-loss and accuracy now AGREE and are both
monotonic in `tau` — log-loss rises and accuracy falls steadily from `tau = 0` (82%
top-1) to `tau = 1` (63%) and beyond. **Resolved: for the image pathway,
`tau ≈ 0` is optimal — the correction should not be applied.** Optimal `score_sharpness`
(5-15) is also far from the package default (0.1). Continuous optimum: `tau = 0.085`,
`score_sharpness = 15.24`.

**Acoustic is unaffected by bug #2** — BirdNET confidence uses `score_type =
"probability"` (already 0-1 bounded), which never calls `.normalize_scores()` at all, only
`similarity`/`similarity_softmax` do. Session 128's acoustic result (37/42 -> 39/42,
correction helps at `tau = 1`) is expected to still hold, but has not yet been
re-validated with the same log-loss calibration procedure used for image — do that before
fully trusting it, since it was only ever an accuracy-based first look.
**Update, Session 133: this expectation did NOT hold** — re-validated on a much larger,
multi-cluster real dataset (2487 windows vs. 42); pooled acoustic optimum is `tau ≈ 0`,
same as image. See Session 133's note below for the full result, including real
per-cluster heterogeneity this 3-species pilot had no way to detect.

**The practical conclusion is not "`tau = 0` is the right default"** — both `correct_
training_bias()`'s own roxygen and this note now say so explicitly: `tau` (and, for
`similarity_softmax`, `score_sharpness`) must be calibrated per data type. Image and
acoustic gave opposite answers (`tau ≈ 0` vs `tau ≈ 1`) from the identical function with
identical defaults on real data — that is itself the strongest evidence yet that a shared
default across data types was never going to be safe.

`devtools::document()`: clean, no signature changes (auto-detection, not a new
parameter). Full TaxaLikely test suite: 497 expectations, 0 failures, 0 errors both
before and after the `assign_scores()` fix.

**Not done**: acoustic re-validation with log-loss (see above — **done Session 133**, see
that note above for the result); wiring the calibrated `(tau, score_sharpness)` into
`TaxaAssign::camera_trap_posterior_workflow.R`'s actual posterior computation (currently
still uses the old `tau = 1.0` default there — still not done as of Session 133).

**Session 128 (2026-07-02): correct_training_bias() wired into the image/acoustic Layer-1 workflow and live-tested — mixed first result**

The two-sessions-overdue wiring from `ecosystem_docs/REENTRY_PROMPT_session127...`, item 1.
`correct_training_bias()` (Session 125, revised Session 127) had never been run against
real classifier output before this session — only a synthetic 3-row fixture.

**Image section** (`image_acoustic_likelihood_workflow.R` Section 1): inserted
`correct_training_bias(count_col = "n_observations")` right after loading TaxaMatch's
checkpoint, before `unreferenced_candidates()` (the reentry note's file reference —
`score_image_workflow.R` — was slightly off; the actual `unreferenced_candidates()` call
site is here, in this script, not TaxaMatch's). `score_image_inat()`'s output already
carries `n_observations` per candidate, so no extra API call was needed.

**Acoustic section** (Section 2): first built the join Session 125's reentry prompt
flagged as never built — `audit_acoustic_coverage(xc_recordings = TRUE)` queried live
against the 9 unique species in the real BirdNET match object (Xeno-canto v3, ~9s), and
its `n_recordings` census column was left-joined onto the match object by `species`
before calling `correct_training_bias(count_col = "n_recordings")`.

**Grounding-truth check (first look, not a calibration — both sets are small):** re-ran
each section's pipeline twice — once with the corrected score, once substituting
`score_uncorrected` back in — to isolate the correction's effect on the winning
candidate, holding everything else constant. Real, live result at `tau = 1.0`:

- **Image** (6 real camera-trap photos): correction changed 2/6 winners; top-1 accuracy
  **fell** from 5/6 (83%) to 4/6 (67%). One flip was wrong-to-wrong (coyote.JPG, already
  a known miss — see Session 124's note); the other turned a correct call wrong: *Sylvilagus
  bachmani* (brush rabbit) got reassigned to *Megascops kennicottii* (a screech owl) once
  bias-corrected. `n_observations` spans 352 to 153,730 across this tiny candidate set —
  a very large range to correct with only 6 photos of signal.
- **Acoustic** (42 real BirdNET detection windows, 3 confusable Calidris sandpipers):
  correction changed 2/42 winners; top-1 accuracy **rose** from 37/42 (88%) to 39/42
  (93%). Both flips were wrong-to-right (one *Calidris mauri* window previously misassigned
  to Killdeer, one *Calidris pusilla* window previously misassigned to Dunlin, both
  corrected to the true species). `n_recordings` (Xeno-canto) spans 44 to 417 — a much
  narrower range than the image path's `n_observations`.

**Interpretation, held loosely:** the correction helped on the data type with narrower
count spread and hurt on the one with wider spread, which is at least directionally
consistent with the "First real-data look" caveat added to `correct_training_bias()`'s
own roxygen this session — but n=6 and n=42 are both far too small to conclude anything
about `tau` itself, and the one harmful image flip is a real, concrete warning sign, not
noise to explain away. **`tau` was NOT changed from the default `1.0`** on the strength of
this alone. Recorded in the function's own "Open caveat" `@details` section (per the
Session 127 reentry prompt's explicit instruction to update that section once a real
check had actually been run) and here, for whoever runs the next real dataset through
this pipeline to compare against.

`devtools::check()` on `TaxaLikely`: 0 errors, 0 warnings, 1 pre-existing note (timestamp
verification, environmental). No R/ source changes besides the roxygen addition to
`correct_training_bias()` — the wiring itself is entirely in
`inst/workflows/image_acoustic_likelihood_workflow.R`.

**Not done**: `tau` was not retuned; the Stage 3 reentry items (real head-data testing,
function-promotion check, Layer-2 wrapper decisions, Drive cleanup check) are unchanged
from Session 127; `TaxaID/CLAUDE.md`'s stale "Planned" label for TaxaAssign was not
touched this session (out of scope — user chose this item specifically over that one).

**Session 127 (2026-07-02): correct_training_bias() revised — logit adjustment (Menon et al. 2020) replaces adaptive per-candidate shrinkage**

Prompted by the user questioning the Session 125 design before it was ever wired into a
real workflow: "it seems like rare taxa would always win over common ones." Worked
through the math live — with `prior_weight = median(n)`, `tau_i = n_i/(n_i+prior_weight)`
behaves almost like a step function pivoting at the candidate set's median count (e.g.
divisor ≈1.02× at n=10, ≈40,300× at n=50,000, ≈487,000× at n=500,000 for
`prior_weight≈1000`). Since real classifier scores are bounded and can't differ by
anything close to that many orders of magnitude, this meant: whenever two candidates
straddle the local median by much, the lower-n one wins essentially by construction,
correct or not — confirming the user's suspicion quantitatively rather than just
intuitively.

Rather than hand-tune the existing formula, ran a 105-agent deep-research literature
review (long-tailed recognition / class-imbalance correction literature) before making
any code change, per the user's own instinct that "this is a well-studied field." Key
findings, all adversarially verified:
- **Menon et al. 2020, "Long-Tail Learning via Logit Adjustment"** (ICLR 2021,
  arXiv:2007.07314) — the standard theoretically-grounded correction: subtract
  `tau * log(pi_i)` from class `i`'s logit (`pi_i` = training-set class frequency),
  equivalent to dividing the raw score by `pi_i^tau`. Critically, `tau` is a **single
  global scalar**, not a per-class adaptive value — the opposite direction from the
  Session 125 design. Fisher-consistent for the balanced/class-uniform error at
  `tau = 1`, derived directly from Bayes' rule; explicitly endorsed for **post-hoc**
  application to an already-trained model (no retraining needed) when label frequencies
  are known — directly matches this package's use case (correcting pretrained
  third-party classifiers, iNaturalist CV / BirdNET).
- The user's "diminishing returns from more data" intuition (their own guess was
  sqrt(n)) does have a real literature analog — **Cui et al. 2019's "effective number
  of samples"**, `(1-beta^n)/(1-beta)` — but it reweights *training loss*, not a frozen
  model's inference-time posterior; structurally the wrong tool for this package's
  post-hoc-only use case (verified against the official implementation).
- No source survived adversarial verification for a direct sqrt(n)/log(n) posterior
  correction; a candidate paper's log-based "Quantity Factor" claim was explicitly
  refuted on reverification.
- Open gap, confirmed by the research (not resolved by it): Menon's Fisher-consistency
  guarantee formally assumes `pi_i` is an accurate estimate of the classifier's *actual*
  training frequency. This package's `n_i` is a noisy **external proxy** (public
  database counts, not the classifier's real internal training counts) — no paper
  directly studies robustness to that gap. `tau` is kept user-tunable, not hardcoded,
  for this reason.

**Mathematical reconciliation**: Menon's `pi_i^tau` uses relative frequency
(`n_i / N_total`), but `N_total` (total training count across all classes) is the same
constant for every candidate being compared within one observation — it cancels out of
any ratio/ranking comparison within a query's candidate set. So dividing by raw `n_i^tau`
instead of `pi_i^tau` is exactly proportionally equivalent here; no need to know or
estimate `N_total`, which this package has no way to obtain for a third-party classifier
anyway. This let the revision keep `correct_training_bias()`'s existing `score / n^tau`
structure and just change what `tau` means (fixed global scalar, default `1.0`) rather
than rewriting the formula shape from scratch.

**Kept from Session 125, deliberately**: NA/zero counts still fall through to the
uncorrected score rather than applying `tau` — pure logit adjustment has no answer for
an unknown `pi_i`, and treating a failed lookup as "no correction" remains the
conservative, defensible default (can't tell a genuinely rare species from a lookup
failure from the count alone).

Test suite fully rewritten to match the new signature: removed the `prior_weight`-default
and `prior_weight`-override tests, added `tau = 0` (disables correction),
`tau` uniformity-across-candidates (the core behavioral change from Session 125), and
`tau > 1` (stronger-than-theoretical correction, matching Menon et al.'s own CIFAR-10-LT
tuned optimum of 2.6) tests. 27 expectations, all passing. `devtools::document()` +
`devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Still not done**: wiring into `image_acoustic_likelihood_workflow.R` or any other
Layer-1 script, and validation against real classifier output — see
`ecosystem_docs/REENTRY_PROMPT_session127...`.

**Session 126 (2026-07-01): Sequence/BLAST Layer-1 workflow — Stage 2 of REENTRY_PROMPT_session124**

`inst/workflows/sequence_likelihood_workflow.R` added — the second script in the
sequence/BLAST mini-chain (TaxaMatch's `blast_sequences_workflow.R`, added the same
session, is the first). This is the architecturally different one among the three
Layer-1 data types: it actually trains the bivariate-normal self-vs-non-self model
(`build_sequence_matrix()` → `train_likelihood_model()`) rather than calibrating a
pre-trained classifier's output like the image/acoustic pathway.

Reference database: live NCBI fetch (`fetch_reference_sequences()`, `max_per_species =
5L`) for 6 real genera spanning 3 fish families (Cottidae, Embiotocidae, Clinidae) —
matching the same real PtConception study system as TaxaMatch's query-side script, not
a separate invented example. Query side reuses TaxaMatch's checkpoint directly (5 real
12S sequences).

Live-tested end to end (both scripts chained in one session, real NCBI calls
throughout), 0 errors after one bug fix (below): 5/5 (100%) top-likelihood accuracy —
`evaluate_likelihoods()`'s winning `specific_candidate` hypothesis matched the true
species for every query, including one genuinely interesting edge case:
`fetch_reference_sequences()`'s genus-level NCBI search for *Rhacochilus* returned 0
sequences (a real query-construction gap — BLAST's own `nt` search independently found
a 100%-identity *Rhacochilus toxotes* record that the narrower reference-fetch query
missed), so that species has no species-specific H1 parameters in the trained model at
all. It still won correctly at inference time via the model's global-mean fallback —
real confirmation that the fallback path (documented in Statistical Design Notes) works
as intended, not a bug. `fetch_reference_sequences()`'s query-construction gap itself
was not fixed this session (out of scope for the workflow-script task; a candidate for
a future investigation if it recurs on other genera).

**Bug found and fixed (by actually running the two-script chain, not by static
review):** the honesty check in this script needs a `true_species` column carried
through on TaxaMatch's checkpoint object, re-joined from it after `evaluate_likelihoods()`
(whose output schema doesn't pass arbitrary columns through). `blast_sequences_workflow.R`'s
own Output block already documented this column as present — but the column was only
ever computed into a local copy inside that script's own honesty-check block, never
actually attached to `taxamatch_blast_match_obj` itself. First run of the two-script
chain failed with `"undefined columns selected"` on the re-join. Fixed in
`TaxaMatch/inst/workflows/blast_sequences_workflow.R` by attaching
`taxamatch_blast_match_obj$true_species <- TRUE_SPECIES[taxamatch_blast_match_obj$observation_id]`
right after `standardize_match_data()`, matching the pattern `score_image_workflow.R`
already uses. Second run: 0 errors.

Other real behavior observed (not bugs): `calibrate_coverage_filter()` reported
near-flat Youden's J (5 unique coverage values on this small reference set) — the
already-documented categorical-coverage message fired as designed; fell back to
`coverage_threshold()`'s quantile shortcut as this script's own coverage-calibration
step anticipates. `train_likelihood_model()` skipped `lme4` hierarchy fitting (only 5
species trained, need ≥10) and warned about singleton references lacking self-matches
(7 of the fetched species had only 1 sequence) — both are the already-documented
graceful-fallback paths (Known Footguns), not new issues.

**Session 125 (2026-07-01): .xc_recording_count() v2 → v3 migration (Stage 1 of REENTRY_PROMPT_session124)**

Fixed the dead-endpoint footgun flagged Session 124. `.xc_recording_count()` (`R/coverage.R`)
switched from `https://xeno-canto.org/api/2/recordings` (404 unconditionally) to
`https://xeno-canto.org/api/3/recordings`, added a required `key` query param read from
`Sys.getenv("XC_API_KEY")`, and rewrote the query from v2 free-text to v3 tag-based syntax
(`gen:{genus} sp:{species} type:call`). Missing-key case now warns explicitly instead of
silently returning `NA` (matching the fix pattern used for `.resolve_llm_fn()` in
`TaxaID/CLAUDE.md`). Response body parsing (`numRecordings` field) unchanged — v3 kept the
same field name as v2.

Live-verified with a real, freshly-registered `XC_API_KEY` (confirmed with the user before
use, per the reentry note's key-provenance caution): `.xc_recording_count("Turdus migratorius")`
→ 430; `audit_acoustic_coverage(xc_recordings = TRUE)` end-to-end on 4 species (2 in-reference,
2 unreferenced) → all 4 returned real non-NA counts (430, 118, 78, 19). `devtools::check()`:
0 errors, 0 warnings, 0 notes.

Stage 1's second item (training-database bias correction) picked up the same session —
see below.

**Session 125 continued: `correct_training_bias()` — training-database bias correction**

Design discussion with the user first (not started from a ticket, per the reentry note's
explicit instruction): confirmed the statistical justification — a classifier trained by
standard cross-entropy estimates a Bayes posterior, so raw score_i ∝ L(obs|species_i) × n_i,
and dividing each candidate's score by its own n_i (rather than pairwise `R = n_i/n_j`
corrections, which don't scale past 2 candidates) corrects every pairwise ratio
simultaneously. Landed on an **adaptive** shrinkage exponent rather than a fixed one:
`tau_i = n_i / (n_i + prior_weight)`, the same functional form already used in
`train_likelihood_model()`'s per-species shrinkage (`w = N/(N+prior_weight)`) — justified
because `n_i` (a public-database count) is only a noisy proxy for the classifier's actual
internal training count, least trustworthy exactly where `n_i` is small. `prior_weight`
defaults to `median(n, na.rm = TRUE)` (self-normalizing to whatever scale the count data
has, rather than an arbitrary constant). A useful side effect: treating a missing/failed
count lookup as `n_i = 0` makes `tau_i = 0` automatically (`n^0 = 1`, no correction) — so
NA handling falls out of the same formula with no special-case branch, rather than having
to decide whether a given NA reflects genuine rarity or a lookup error.

`correct_training_bias()` added (`R/correct_training_bias.R`): overwrites `score_col`
(default `"score_original"`, matching `assign_scores()`'s own default) in place with the
corrected value, so no downstream call site needs to change; preserves the pre-correction
value under `score_uncorrected`; adds `n_used`/`tau_used` diagnostics. Confirmed via
`TaxaMatch::score_image_workflow.R`'s real output contract that the working column really
is named `score_original` (not `score`) by the point this would run — the design
conversation's placeholder name was corrected before implementation.

22 offline unit tests (`test-correct-training-bias.R`), all passing: correction direction
(favors low-n over high-n candidates), NA/zero-count fallthrough, all-NA-counts case,
missing-count_col warning, default-vs-explicit `prior_weight`, and input validation.
`devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Not done yet**: not wired into the Layer-1 `image_acoustic_likelihood_workflow.R` /
`score_image_workflow.R` / `score_acoustic_workflow.R` scripts, and not validated against
real classifier output (only a synthetic 3-row fixture so far) — the acoustic side also
still needs the `n_recordings` join from `audit_acoustic_coverage(xc_recordings = TRUE)`
onto the match object by taxon, which nothing does yet. See the reentry prompt for the
concrete next steps.

**Session 124 (2026-07-01): Layer-1 image/acoustic likelihood workflow**

`inst/workflows/image_acoustic_likelihood_workflow.R` added — consumes TaxaMatch's real
iNat CV (image) and BirdNET (acoustic) checkpoints from `score_image_workflow.R` /
`score_acoustic_workflow.R`, via the same `unreferenced_candidates()` + `assign_scores()`
pathway this file's docs already noted is identical for both data types. Live-tested,
0 errors: image section 5/6 (83%) correct on real camera-trap photos (5 mammal species,
4 families); acoustic section 37/42 (88%) correct on real BirdNET output for 3
confusable Calidris sandpipers. See `TaxaMatch/CLAUDE.md`'s Session 124 note for the
full real-data provenance and bugs found while building the TaxaMatch side.

Confirmed live: `assign_scores(score_type = "similarity_softmax")` (image, unbounded
`combined_score`) and `score_type = "probability"` (acoustic, already 0-1 bounded
BirdNET confidence) both ratio-normalize by the winning candidate's own score — the
winner's `score_likelihood` is therefore always exactly 1.0 by construction; the
meaningful comparison across observations is which taxon won, not the likelihood
magnitude. Not a bug, but non-obvious enough to be worth stating plainly here.

Also found (not fixed, out of scope for this task): `.xc_recording_count()` calls a
dead Xeno-canto v2 endpoint — see the new Known Footguns entry above.

**Session 123 (2026-07-01): audit_barcode_coverage() "Common mistake" doc fix (no logic change)**

No function behavior changed — this was a workflow-usage bug, not a package defect.
Root cause confirmed empirically against real Mugu cached data (`match_obj`/`reference_df`/
`coverage` RDS files): *Mustelus mosis* was both an H1 BLAST `specific_candidate`
(accession NC_077464, a complete 16755bp mitogenome, 174bp aligned region, 98.28% identity)
and reported "unreferenced" by `audit_barcode_coverage()`. Cause: three real workflows
(`PtConceptionWorkflow_12S.R`, `PtConceptionWorkflow_18S_2.R`, `MuguFishWorkflow.R`) all
passed the length-curated `reference_df` (built for `build_sequence_matrix()`, which
correctly excludes full mitogenomes from the alignment training set) as
`audit_barcode_coverage()`'s `match_df` skip-list argument, instead of the actual match
object. A species whose only NCBI record is a long sequence is therefore absent from the
skip-list and fails the barcode-length-restricted reverse search, even though BLAST
(unconstrained by length) already matched it correctly. `run_bayesian_pipeline()` was
already unaffected — it builds its skip-list from its own `match_df` parameter (the real
match object), never from a training `reference_df`.

Added a `@param match_df` clarification plus a "Common mistake" `@details` subsection to
`audit_barcode_coverage()` (`R/coverage.R`) documenting the exact mechanism with this case
as a worked example, so it does not recur a fourth time. All three real workflows updated
to pass `match_obj`/`match_obj_restored` instead of `reference_df`; each workflow's
diagnostic NOTE (checking for species in both the match object and
`coverage$unreferenced`) kept as a post-fix sanity check rather than removed.
`devtools::check()`: 0 errors, 0 warnings.

Sessions 30–94 archived in `ecosystem_docs/session_notes/TaxaLikely_sessions.md`.

**Session 100 (2026-06-03/04): Trivariate revert; coverage sigma-inflation (score_likelihood_cov)**

Trivariate coverage model (rejected): explored making coverage a third dimension of the
bivariate normal, but premise validation on `build_sequence_matrix()` output showed H1
(within-species) training pairs are nearly all coverage ≈ 1 (mean 0.991, var 0.002) while
H2 cross-species pairs are much more variable (mean 0.908, var 0.041). Because there is
no within-H1 coverage variation, the model cannot estimate a coverage–score relationship.
Trivariate approach reverted; coverage remains a hard filter only via `min_coverage`.

New: `score_likelihood_cov` column added to `evaluate_likelihoods()` output. Applies a
post-hoc sigma inflation at inference time using a prior (binomial SE argument):
σ_eff = σ / sqrt(coverage). Only the [1,1] element of H1_Sigma is inflated; H2/H3 sigmas
are global fixed parameters and are not modified. Key behavior: for scores near the H1
mean (good within-species matches), widening sigma lowers the peak density → negative
delta (primary intended effect — penalises good matches observed at low coverage). For
scores far below the H1 mean (cross-species matches), widening sigma fattens the left
tail → positive delta (secondary, low-relevance effect). Crossover at exactly ±1 sigma
from the H1 mean. Column added as a parallel output only (non-breaking); `score_likelihood`
is unchanged and remains the default for TaxaAssign unless the user switches.

Other changes this session: Workflow 3 fully rewritten (removed stale trivariate
references; added coverage-by-hypothesis-type diagnostic; added demo of
score_likelihood_cov using within-species pairs with coverage < 0.99). README updated
with `score_likelihood_cov` in the Quick Start output and a Statistical Design bullet
explaining the formula, direction of effect, and why coverage is not a model dimension.
`train.R` minor cleanup (roxygen, h2_sigma_mat moved outside conditional).

**Session 105 (2026-06-10): fetch_reference_sequences() cache key fix + audit_barcode_coverage() checkpoint/resume**

`fetch_reference_sequences()`:
- `cache_dir` default changed from `tempdir()` to `tools::R_user_dir("TaxaLikely", "cache")`
  for cross-session persistence.
- Per-taxon cache keys now include `eff_min_len`, `eff_max_len`, and `max_date` in the
  filename. Previously changing these parameters returned stale cached data. Both the
  priority-species key (`priority_{name}_{bc}_l{min}_{max}_d{date}_meta.rds`) and
  the broader-taxa key (`{name}_{bc}_l{min}_{max}_d{date}_meta.rds`) updated.

`audit_barcode_coverage()`:
- `cache_dir` param added (default `tools::R_user_dir("TaxaLikely", "cache")`; NULL disables).
- `.coverage_checkpoint_path()` internal helper: deterministic path from genera count/nchar-sum,
  barcode_term, len_range, max_date, target_rank. Changed parameters auto-start fresh.
- Checkpoint (named list of completed genus records) saved after each genus — both the
  early-exit (no species found) and normal completion paths.
- On resume, already-completed genera are loaded from checkpoint and skipped.
- Checkpoint deleted on clean completion.

**Session 119 (2026-06-24): audit_inat_coverage() + audit_acoustic_coverage(xc_recordings)**

`audit_inat_coverage()` added to `R/coverage.R`:
- New exported function. Given a `species_list` (prior taxa not in match data), queries the
  iNaturalist taxa API (`GET https://api.inaturalist.org/v1/taxa?q={name}&rank=species&per_page=1`)
  for each species. Returns `list(census, unreferenced)` with same structure as
  `audit_barcode_coverage()`.
- Census columns: `species`, `taxon_id`, `matched_name`, `n_observations`, `in_inat`,
  `cv_model_included` (n_obs >= `cv_threshold`, default 100L), `unreferenced`, `in_match_data`.
- Optional `match_df` param annotates `in_match_data`. Optional `api_token` (env
  `INAT_API_TOKEN`); 401 → stop with token refresh message.
- 0.3s `Sys.sleep()` rate limit per species. `verbose = FALSE` param for progress messages.
- Internal helper `.inat_species_info()` wraps `httr2` request; returns list with `taxon_id`,
  `matched_name`, `rank`, `n_observations`, `found`.

`audit_acoustic_coverage()` enhanced:
- New `xc_recordings = FALSE` param. When TRUE, queries Xeno-canto v2 API
  (`GET https://xeno-canto.org/api/2/recordings?query={name}`) per species; adds `n_recordings`
  column to census (NA when FALSE). 1s `Sys.sleep()` rate limit per species.
- Internal helper `.xc_recording_count()` wraps `httr2` request; parses `numRecordings`
  string → integer; returns `NA_integer_` on any failure.

`httr2` moved from Suggests to Imports in `DESCRIPTION` to support the new API-calling
coverage audit functions.

`devtools::check()`: 0 errors, 0 warnings, 1 pre-existing note (stale top-level .rds file).

**Session 121 (2026-06-26): Per-species sigma floor + Mahalanobis alpha 1e-6 → 0.001**

Two inference improvements in `.evaluate_one_query()` / `evaluate_likelihoods()`:

Per-species sigma floor: `use_sigma[1,1]` now floored at `global_sigma[1,1]` before
H1 density evaluation. Fixes species with artificially tight reference distributions
(near-identical NCBI clones) silently dropping below `ratio_threshold`.

Mahalanobis alpha default changed from `1e-6` to `0.001`: The chi-squared outlier
check (2 df) now rejects H1 candidates at p < 0.001 rather than p < 1e-6. Motivation:
`1e-6` admitted freshwater Cyprinidae (91–93% identity in a marine sample; p ≈ 0.00026)
as spurious H1 rows. `0.001` drops them (0.00026 < 0.001) while retaining legitimate
borderline H1 hits (e.g. Leptocottus armatus at 99%; p ≈ 0.009 > 0.001). Unlike
`ratio_threshold`, this check is H1-intrinsic — it asks only whether the query is
consistent with H1's own distribution, independent of H2/H3 densities. `ratio_threshold`
default left at `0.01` in function signatures for backwards compatibility; workflows
that use `ratio_threshold = 0` rely solely on this alpha check.

449 tests pass; 0 failures.

