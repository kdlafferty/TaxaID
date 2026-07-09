# CLAUDE.md — TaxaID Ecosystem
# Ecosystem-level context for Claude Code. Auto-loaded from any package subdirectory.
# Package-specific context lives in each package's own CLAUDE.md.
# Last updated: 2026-07-09 (Session 147, branch `main` -- fifth parameter-audit punch-list
# family (score floors). New diagnostics/score_floor_roc_sweep.R uses real classification
# ground truth (every pair in the real 12S seq_matrix reference data has known species/genus/
# family identity) to show raw percent-identity score alone cannot discriminate a species from
# its closest congener at almost any real-world threshold -- confirming and sharpening the
# ecosystem's own "Framing B verdict" memory at the specific parameter level. Surfaced a real,
# higher-stakes gap along the way: TaxaAssign::score_consensus()'s rank_thresholds defaulted to
# NULL, so a caller with no explicit override got zero score-based species-vs-congener
# protection, silently. Fixed: rank_thresholds now defaults to the conventional GITA/Jonah
# Ventures thresholds, auto-rescaled by /100 if the score column looks like a 0-1 proportion
# scale (matching TaxaLikely's existing scale-detection convention). Verified against every
# real call site and test before running them; devtools::test() 539/539 unchanged,
# devtools::check() clean. See TaxaAssign/CLAUDE.md's Session 147 note for the full record.
# Session 146, branch `main` -- fixed a real, silent LLM-response-
# truncation risk in TaxaAssign::assign_taxa_llm() that Session 145's sensitivity work surfaced:
# 4/5 real 30-taxon batches truncated at call_api()'s default max_tokens=3000, silently falling
# back to uniform priors with only a warning. .parse_taxa_response() now detects the truncation
# signature specifically and gives an actionable warning; taxa_per_call's default lowered
# 30->15 in both assign_taxa_llm() and run_llm_pipeline() (which forwards it), corroborated by
# TaxaFlag::review_assignments() having independently made the identical 30->15 fix for the same
# failure mode in an earlier session. suggest_unreferenced_species() still defaults
# taxa_per_call=30L, deliberately not changed (different, simpler response shape; risk not
# confirmed there). devtools::check() clean, 539 tests unchanged. See TaxaAssign/CLAUDE.md's
# Session 146 note for the full record.
# Session 145, branch `main` -- empirical sensitivity check for the
# fourth parameter-audit punch-list family: TaxaAssign::assign_taxa_llm()'s score_sharpness,
# unknown_lik_weight, prior_phi, absent_detection_prob. Small refactor first (new internal
# .merge_llm_priors() helper, behavior-preserving, 539 tests unchanged) to enable a cheap sweep
# against one real LLM response (499 real PtConception 12S observations, 5 real Anthropic API
# calls -- no usable real assign_taxa_llm() checkpoint existed anywhere beforehand). Finding:
# these four parameters mostly shape CONFIDENCE (consensus_posterior), not WHICH taxon wins
# (resolution rate was flat within ~1.5 points across every grid). unknown_lik_weight has the
# largest real effect (mean winning posterior 0.997->0.911 across a plausible range);
# score_sharpness had almost none; prior_phi's tiered default matched a flat scalar almost
# exactly (a real, still-open question about whether the tiering earns its keep);
# absent_detection_prob (tested via a disclosed synthetic overlay, since no real workflow here
# uses known_absent) showed no aggregate effect but is the weakest/most diluted result. Also
# surfaced two real, general gaps along the way (not fixed, flagged for later): TaxaTools's LLM
# provider auto-detection doesn't activate in a plain Rscript session even with
# library(TaxaTools) loaded; call_api()'s max_tokens=3000 default truncated 4/5 real 30-taxon
# LLM responses at the documented taxa_per_call=30 batch size. See TaxaAssign/CLAUDE.md's
# Session 145 note for the full record.
# Session 144, branch `main` -- empirical sensitivity check for
# TaxaAssign::posterior_consensus()'s min_posterior/cumulative_threshold defaults (0.05/0.90)
# against a real 3,000-observation PtConception 12S posterior_df. Finding: min_posterior does
# real, roughly linear work (+8.2 resolution-rate points sweeping 0->0.20); cumulative_threshold
# does comparatively little independent work once a reasonable min_posterior floor exists
# (-3.3 points sweeping 0.70->0.99, non-monotonically). The two interact sharply only in the
# unrealistic min_posterior=0 + cumulative_threshold=0.99 corner. Measures resolution RATE, not
# ACCURACY -- no ground-truth-validated observations were available to check correctness. New
# reusable diagnostics/posterior_threshold_sweep.R. See TaxaAssign/CLAUDE.md's Session 144 note
# for the full record, including why the sweep was subsampled to 3,000 of 13,483 real
# observations (the full sweep was twice interrupted at 15-17 min in this session's background-
# task setup).
# Session 143, branch `main` -- TaxaAssign::join_priors()/
# posterior_consensus()/run_bayesian_pipeline()/run_llm_pipeline() no longer have a silent
# default for backbone_id anywhere it's actually used to reconcile taxonomy against an
# external backbone -- join_priors() gains a new required backbone_id param (no default,
# errors if omitted), replacing a hardcoded backbone_id = 4L; posterior_consensus()'s default
# changed from 11L to NULL (errors only when lookup_missing_taxonomy = TRUE); the two pipeline
# wrappers lost their 4L default entirely since both forward it unconditionally downstream.
# Prompted by a parameter audit flagging the 4L (run_bayesian_pipeline) vs 11L
# (posterior_consensus) default mismatch as a possible correctness bug -- traced first and
# confirmed it was NOT live (the value is always explicitly forwarded through
# .run_consensus_and_report(), so posterior_consensus()'s own default was never actually
# reached via that path), but the user's design call was that the correct backbone depends on
# which backbone the caller's own input data used, which varies by project, so no such
# function should have a silent default. TaxaTools::fill_higher_ranks()/
# escalate_taxonomic_rank() deliberately kept their existing 4L/11L primary/fallback pair
# (a resolution strategy, not an input-backbone assumption). All ~15 real call sites across
# vignettes, workflow scripts, and TaxaWizard snippets + metadata updated; devtools::check()
# clean, 539 tests passing. See TaxaAssign/CLAUDE.md's Session 143 note for the full record,
# including a pre-existing, unrelated TaxaWizard metadata bug found and flagged (not fixed) 
# along the way.
# Session 142, branch `main` -- TaxaLikely::trim_to_amplicon() now
# supports the real eDNA/metabarcoding COI mini-barcode (Leray et al. 2013 mlCOIintF paired
# with Meyer 2003's dgHCO2198, registry key `coi-leray`), resolving the inosine blocker Session
# 141 explicitly left unimplemented (Geller et al. 2013's jgHCO2198 uses inosine, which
# Biostrings::DNAString cannot represent -- Meyer's older degenerate reverse primer binds the
# same site without it, a real published pairing, not an invented workaround). Prompted by the
# user asking to learn about the mini-barcode's known discriminatory-power limitations before
# deciding whether the implementation effort was worth it; empirically confirmed 365bp on real
# Drosophila melanogaster mtDNA, reconciling exactly to the commonly-cited "313bp Leray
# fragment" once both primers are excluded. Bare "COI" is now deliberately ambiguous between
# coi-folmer and coi-leray. See TaxaTools/CLAUDE.md's and TaxaLikely/CLAUDE.md's own Session
# 142 notes for the full literature review and verification record.
# Session 141, branch `main` -- TaxaLikely::trim_to_amplicon()
# (Session 140) now covers every mitochondrial/chloroplast marker in
# TaxaTools::barcode_length_defaults (16S, COI, cytb, rbcL, matK, trnL), not just MiFish-12S.
# Prompted by the user asking directly whether primer-trimming was worth it for 12S at all
# (yes -- safe fallback, real production impact already observed, low false-positive risk)
# and to work through the remaining mito/chloroplast markers (nuclear genes -- 18S, ITS,
# ITS2 -- explicitly excluded per the user's own instruction, no canonical primer pair
# exists for any of them). Each new primer pair verified two ways: cross-checked against
# 2-3 independent literature sources, AND empirically tested with Biostrings::matchPattern()
# against a real GenBank mitogenome/chloroplast genome fetched live via NCBI eutils -- this
# caught two real errors a literature check alone would have missed (a wrong cytb amplicon
# length two secondary sources agreed on but real data contradicted; a genuine
# forward/reverse primer mislabeling in an otherwise-authoritative matK primer table,
# resolved by testing both orientations against real chloroplast DNA). No code changes
# needed in TaxaLikely itself -- trim_to_amplicon() was already generic over any
# barcode_term with a registered primer pair. See TaxaTools/CLAUDE.md's and
# TaxaLikely/CLAUDE.md's own Session 141 notes for the full record.
# Session 140, branch `main` -- implements
# ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md's general (taxon-centric)
# fix: new TaxaFetch::fetch_occurrences_by_taxon() unions each candidate taxon's own search
# geometry and combines taxa sharing identical geometry into one GBIF call, replacing
# `TaxaID_Workflow_Template_TEST.R` Section 3's old per-observation/site fetch loop with a
# two-pass design (define all groups' geometry first, then fetch once per taxon key across
# the whole scope). `TaxaFetch::stack_occurrences()` also gained a `gbifID` dedup step
# (defense-in-depth; confirmed no dedup existed anywhere in the GBIF occurrence pipeline
# before adding it, and that `TaxaMatch::standardize_match_data()` is an unrelated pipeline
# -- classifier match records, not occurrence data -- so the gap was real, not stale). See
# TaxaFetch/CLAUDE.md's Session 140 note for the full record, including the isolated-logic-
# test verification against Session 139's own real bundled checkpoint data and the user's own
# live RStudio confirmation the same session (4 taxon keys correctly collapsed to 2 GBIF
# queries on real data).
# Session 140 continued (2026-07-06): implements
# ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md -- new
# TaxaLikely::trim_to_amplicon() locates primer-binding sites (verified MiFish-U/E only,
# Miya et al. 2015) in over-length reference sequences (e.g. full mitogenomes) via
# Biostrings in-silico PCR and extracts just the amplicon, instead of
# build_sequence_matrix()'s length filter discarding the whole sequence outright -- the
# deeper fix for the exact "No H1 pairs found" mitogenome-contamination problem the Session
# 139 note below describes fixing with length-exclusion only. Package placement (TaxaLikely,
# not TaxaFetch/TaxaMatch) argued through explicitly with the user before starting; new
# TaxaTools::barcode_primer_defaults registry deliberately populated with only MiFish-U/E
# (the sole marker with real production use in this ecosystem) rather than attempting all
# `barcode_length_defaults` markers -- 18S explicitly excluded since no single canonical
# primer pair exists to verify. See TaxaLikely/CLAUDE.md's and TaxaTools/CLAUDE.md's own
# Session 140 notes for the full record.
# Session 139, branch `main` — Phase 6 live-testing of
# `TaxaID_Workflow_Template_TEST.R` (Session 138's reentry plan) surfaced and fixed three
# more real bugs beyond Session 138's own scope. (1) Section 3/5 conflated "multiple
# different observations sharing a bounding box" with "one observation detected at
# multiple sites" -- branching now keys on distinct observation_id count, not row count;
# Section 5 generates priors per real site instead of an averaged centroid. (2) Section
# 6a built its reference sequence database by reusing whatever accessions BLAST itself
# hit, with no length control -- GenBank mixes short barcode submissions with full
# mitogenomes for the same species, and build_sequence_matrix()'s length filter silently
# dropped every within-species pair in this template's real bundled data, hard-failing
# model training ("No H1 pairs found"). (3) The same raw-BLAST-reuse approach also pulled
# in a flagged lab contaminant (Salmo salar) that had already been excluded from
# decontaminated_table -- a genuine disconnect between the analysis candidate set and the
# reference-fetch candidate set. Fixed (2) and (3) together: Section 6a now calls
# `TaxaLikely::fetch_ncbi_reference_sequences()`, deriving candidate taxa from the
# already-decontaminated `match_obj` and filtering reference sequences by barcode-
# appropriate length before download (mitogenomes never fetched at all) -- verified live
# against real NCBI data, training now succeeds (12 within-species pairs, up from 0). A
# deeper, more general version of the mitogenome problem (in-silico PCR to extract the
# amplicon region from an over-length sequence instead of discarding it outright) was
# deliberately scoped out as its own design task, not implemented --- see
# `ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md`. A related,
# separate GBIF-fetch-efficiency discussion (taxon-centric query grouping to avoid
# redundant/overlapping GBIF searches) is captured in
# `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` -- also not yet
# implemented, scope not yet chosen with the user.
# Session 139 continued (2026-07-06): continued live testing surfaced two more real issues
# and one usability redesign, all found by actually using the pipeline, not reading code.
# (a) `TaxaMatch::build_site_table()`'s default `spatial_group_id` (previously the row's own
# `observation_id`) redesigned to group by exact `(lat, lon)` match instead -- a grid-
# snapping alternative was tried first and rejected after it collapsed four genuinely
# distinct real observations into one default cluster on this template's own bundled data.
# New `is_default_group` marker column replaces a fragile string-comparison heuristic;
# `.next_spatial_group_number()` keeps default-assigned and interactively-drawn group labels
# from colliding. (b) The spatial-grouping applet itself redesigned for clarity:
# `TaxaTools::define_search_polygon()` gained customizable `title`/`done_label`/
# `cancel_label` params (backward compatible) so `group_observations_by_bbox()` can say
# "Group These Points"/"No More Groups" instead of generic "Done"/"Cancel", show per-group
# progress in the title, and open one zoom step further out so the starting box is actually
# visible -- prompted by the user reflexively clicking "Done" on the unshrunk starting
# square and merging far more observations into one group than intended. (c) A real,
# previously-latent bug fixed along the way: `TaxaID_Workflow_Template_TEST.R`'s Section 3
# never checked whether a cancelled search-area gadget returned `NULL` before passing it to
# `TaxaFetch::get_gbif_occurrences()`, crashing several calls downstream with a confusing
# error instead of a clear one. See `TaxaMatch/CLAUDE.md`'s and `TaxaTools/CLAUDE.md`'s own
# Session 139 notes for full detail; the GBIF-fetch-efficiency reentry prompt above also
# gained a note on why this session's applet work makes a "define all boxes, then fetch"
# two-pass split a real prerequisite for that document's taxon-centric design, still not
# implemented.
# Session 138 (2026-07-05), branch `single-observation-pipeline` — Phase 5 of
# the observation-pipeline-wiring plan: multi-site posterior combination.
# `TaxaAssign::join_priors()`'s final dedup was silently collapsing a genuine multi-site
# observation (the same detection recovered at more than one real site, surfaced by Session
# 137's Phase 4 DNA/BLAST wiring) to one row per candidate per its own best site, discarding
# the site it was actually detected at — fixed by making that dedup grid_id/main_habitat-
# aware. New `TaxaAssign::combine_multisite_priors()` recombines the resulting per-site rows
# via precision-weighted combination in logit space (empirically shown to correctly discount
# a low-confidence/sparse-data site, unlike either of the two options the prior session's
# reentry prompt had proposed — see `TaxaAssign/CLAUDE.md`'s Session 138 note for the full
# empirical comparison). Wired into `TaxaID_Workflow_Template_TEST.R` Section 7.
# Session 137 continued yet further (same day, earlier) — Phase 4 (DNA/BLAST half) of the observation-pipeline-wiring plan:
# `TaxaMatch::join_event_site_metadata()` added, producing a `site_df` for
# `build_site_table()` from an event-level detections table joined against a
# user-maintained site-metadata table — generalizes the ecosystem's existing
# blank-identification lookup-table pattern (`BLANKS_MARCH`/`BLANKS_AUG`,
# `control_samples`) to carry site coordinates. Data-type-agnostic by design (DNA/BLAST
# and acoustic reduce to the same join), but only the DNA/BLAST half is wired live this
# session — `TaxaID_Workflow_Template_TEST.R`'s Section 2.5 now uses the bundled
# `Reads_Table`'s real `sample_1`/`sample_2` columns as genuinely different sites,
# surfacing and fixing a real latent bug in Section 3's multi-member-vs-singleton
# branching (`build_site_table()` hardcodes `spatial_group_N = 1L` per row regardless of
# duplicates; branching now uses `nrow(group_sites)` instead of the stored column). The
# acoustic half stays deferred — no real multi-site BirdNET deployment data exists yet to
# wire against honestly; the user described two plausible real shapes (fixed BirdWeather-
# style recorders vs. multi-site field-trip submissions) but was explicitly unsure which
# applies, so `score_acoustic_workflow.R` only gets a documentation pointer. See
# `TaxaMatch/CLAUDE.md`'s Session 137-continued note for the full record.
# Session 137 continued further (same day, earlier) — Phase 3 of the observation-
# pipeline-wiring plan:
# `TaxaMatch/inst/workflows/score_image_workflow.R` gains an `OVERRIDE_SITE_LATLNG` flag
# (default TRUE, matching this script's bundled EXIF-less trail-camera photos) so the
# previously-unconditional site-coordinate override is now explicit rather than silently
# stomping on real per-photo EXIF GPS for other users' photo sets, plus a new
# `build_site_table()` call producing a checkpointed `image_site_table`. Live-verified
# both flag settings against the real bundled 52-photo set (82%/60% top-1 accuracy,
# matching prior documented results — no regression). See `TaxaMatch/CLAUDE.md`'s Session
# 137 note for detail.
# Session 137 continued (same day, earlier) — Phase 2 of the observation-pipeline-wiring
# plan: `inst/TaxaID_Workflow_Template_TEST.R`
# (the master 8-section workflow template) now wires spatial grouping end to end. New
# Section 2.5 builds a `site_table` (`TaxaMatch::build_site_table()` +
# `group_observations_by_bbox()`); Section 3's occurrence fetch branches per
# `spatial_group_id` (pooled bbox fetch for multi-member groups, per-observation
# taxonomic-escalation fetch via `TaxaTools::escalate_taxonomic_rank()` for singletons);
# Section 5 generates `TaxaExpect` priors once per group at that group's own resolved
# grid cell instead of one global `SITE_GRID_ID`; Section 7 joins each observation
# against its own group's priors (`join_priors()`'s existing multi-site data-frame path)
# and adds a new `TaxaAssign::update_prior_from_consensus(spatial_group_map = site_table)`
# call (previously not invoked anywhere in this template). The DNA/BLAST pathway still
# has no real per-observation site metadata (Phase 4, deferred) — every observation is
# placed at one hardcoded `STUDY_LAT`/`STUDY_LON` as a documented placeholder, so real
# multi-site behavior isn't exercised by this template's bundled test data yet, only the
# wiring itself. See `TaxaID/CLAUDE.md`'s own Session 137-continued note below for the
# verification approach and what's still deferred (Phases 4-7).
# Session 137 (earlier in the same day) — TaxaTools::escalate_taxonomic_rank() added: the
# escalation-ladder function (broaden genus -> family -> order when a singleton's own
# genus has no reference/occurrence data), Phase 1 of the same plan. Live-verified against
# real NCBI data for the PtConception 12S cases and the bobcat-photo case. See
# TaxaTools/CLAUDE.md's Session 137 note for detail.
# Session 134b, branch `single-observation-pipeline` — after
# reviewing Session 134's automatic-spatial-grouping implementation, the user raised package-
# placement questions before committing (see
# ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md). Resolved: the shared
# interactive polygon gadget only needed a small additive generalization (color the points
# overlay by group; reopen a previous polygon for reshaping) to serve both TaxaFetch's
# search-area purpose and TaxaMatch's spatial-group purpose, so `define_search_polygon()`
# moved TaxaFetch -> TaxaTools and `group_observations_by_bbox()` moved TaxaFetch -> TaxaMatch
# (it operates on TaxaMatch::build_site_table()'s output; a spatial-grouping concern, not a
# fetch concern). `group_observations_by_bbox()` also substantially reworked: `spatial_group_id`
# now defaults to the observation's own `observation_id` (set by `build_site_table()`, not
# invented by the grouping function), last-drawn-wins overlap resolution with a warning, and a
# new end-of-loop review/edit/delete step. New `TaxaMatch::assign_spatial_group()` manual
# helper for metadata-known groupings. All three packages (TaxaTools, TaxaFetch, TaxaMatch)
# plus TaxaAssign (doc-only cross-reference fix) `devtools::check()`-clean. Still open for a
# follow-up session: the search-area-vs-spatial-group reconciliation, fetch-scope branching
# (the escalation-ladder engineering work), the Reads-table relocation, and the TaxaAssign
# (observation_id, site) schema question -- see the reentry prompt and each touched package's
# Session 134b note for the full record. Session 133 — acoustic tau/score_sharpness re-calibrated on a real, deliberately-designed 24-species/8-cluster/2487-detection-window dataset (up from a 3-species/42-window pilot); Session 128/129's "acoustic wants tau≈1, opposite of image" conclusion did NOT hold — pooled acoustic optimum is tau≈0, same as image, though per-cluster results are genuinely heterogeneous and one global tau may not be appropriate. No current real-data evidence supports tau>0 as a default for either data type. See TaxaLikely/CLAUDE.md's Session 133 note and ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md for the full record. Session 132 — TaxaMatch non-portable camera-trap filenames fixed. Session 129 — real assign_scores() score-scale bug found and fixed; TaxaExpect crash fixes for sparse real data; new TaxaFetch::get_gbif_occurrences() unified wrapper; first real TaxaAssign posterior run for the camera-trap species set. See ecosystem_docs/REENTRY_PROMPT_session129_calibration_resolved.md for that record.)

---

## ⚙️ Claude Code Behavior
- After completing any task, play a completion sound: `afplay /System/Library/Sounds/Glass.aiff`
- Always ask before making changes to multiple *existing* files at once, or before any deletions
- Run `devtools::check()` after any substantive edits to a package

---

## 📋 Pending Documentation Tasks
- **pkgdown sites**: No `_pkgdown.yml` exists for any package. Per the MEE TaxaID
  manuscript plan (manuscript-context.md in Cowork), the paper will follow the
  aniMotum precedent — a short "Application"-style paper that points readers to
  package vignettes/docs for depth rather than including a full tutorial. This
  requires each package (at least TaxaTools, TaxaFetch, TaxaHabitat, TaxaMatch,
  TaxaLikely, TaxaExpect, TaxaAssign, TaxaFlag) to have a working pkgdown site
  before submission. Flagged June 2026 during manuscript planning.

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
| R library | `~/Library/R/4.0/library` — set via `R_LIBS_USER` in `~/.Renviron`, **not** `~/.Rprofile` (corrected Session 134b; see that session's TaxaTools/CLAUDE.md note). This project has its own `TaxaID.Rproj` + project-level `.Rprofile`, which RStudio sources *instead of* `~/.Rprofile` when the project is open — so `~/.Rprofile`'s own `.libPaths()` call (pointing at a directory that doesn't even exist, `~/Library/R/4.5-arm64/library`) never actually runs in this project. Confirmed directly: a real `R` session started from the project root resolves `.libPaths()[1]` to `~/Library/R/4.0/library`, and that's where `find.package()` finds every TaxaID package. `Rscript` (no project context) also lands here by default via `R_LIBS_USER`. The system default library (`/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library`, i.e. `.Library`) is a same-R-version fallback, not the primary install target — don't rely on it matching what's actually loaded. |
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
| TaxaAssign | Calculate posterior probability for a taxonomic assignment given a likelihood and a prior | In development |
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
**end your response with an explicit "To apply these changes" block using this exact pattern:**

**If only TaxaTools changed:**
```r
.rs.restartR()
devtools::install("~/My Drive/Rscripts/projects/TaxaID/TaxaTools")
.rs.restartR()
```

**If multiple packages changed, or if unsure which downstream packages are affected:**
```r
.rs.restartR()
source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
.rs.restartR()
```

**Always include two `.rs.restartR()` calls** — the first clears the stale session before
installing, the second ensures the freshly installed packages are loaded cleanly.
The `source()` line installs all packages in dependency order without opening each project.
Do not tell the user to use Session → Restart R or Cmd+Shift+F10 (does not work on this machine).

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

### `.resolve_llm_fn()` default silently degrades under fully-namespaced calls (Session 123)
`assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`, `suggest_unreferenced_species()`
(TaxaAssign) and `review_assignments()` (TaxaFlag) all default `llm_fn` to
`getOption("TaxaID.llm_fn", TaxaTools::call_api)`. `call_api()`'s provider
auto-detection depends on `TaxaTools::.onAttach()` having run, which only happens via
`library(TaxaTools)` — never via `TaxaTools::function()`. Code that calls these
functions using only namespaced (`::`) calls therefore never triggers auto-detection,
and `call_api()` **silently falls back to uniform/degraded output instead of
erroring**. No warning, no error — just a suspiciously uniform result. Caught only by
noticing the output looked wrong, in the TaxaID Layer-1 workflow scripts (which use
namespaced calls exclusively). Fix: always pass `llm_fn` explicitly when calling any
of the five functions above from a fully-namespaced script:
```r
llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
```

### `library(TaxaTools)` alone does not activate provider auto-detection in a plain `Rscript` session (found Session 145)
The Session 123 footgun above prescribes `library(TaxaTools)` as the fix for `call_api()`'s
provider auto-detection. That's necessary but **not sufficient** in a non-interactive
`Rscript` session (as opposed to RStudio): confirmed directly that `library(TaxaTools);
call_api(prompt)` still errors `"no LLM provider configured"` even with a real
`ANTHROPIC_API_KEY` set in `~/.Renviron`, because `getOption("TaxaID.provider")` /
`getOption("TaxaID.llm_fn")` stay `NULL` after attach in that context. Whatever sets those
options interactively (RStudio session init, or an `.Rprofile` hook) doesn't fire for a bare
`Rscript` batch run. Not investigated further (out of scope for the session that found it) --
the workaround is to pass an explicit provider:
```r
llm_fn <- function(prompt) TaxaTools::call_api(prompt, provider = "anthropic")
```
Relevant any time you write a one-off `Rscript` (not run inside RStudio) that needs to make a
real LLM call — e.g. diagnostic/sensitivity-sweep scripts under `diagnostics/`.

### Xeno-canto v2 API is dead; v2→v3 migration in Session 87 missed one call site (found Session 124, FIXED Session 125)
`ecosystem_docs/NAME_CHANGE_HISTORY.md` records the v2→v3 migration as done in Session 87
(`fetch_reference_recordings()` updated), but `TaxaLikely::.xc_recording_count()`
(`R/coverage.R`, added Session 119 — *after* that migration) was never updated and called
the dead v2 endpoint. Because `.xc_recording_count()` checked `resp_status != 200L` and
returned `NA_integer_` silently, `audit_acoustic_coverage(xc_recordings = TRUE)` had
returned `NA` for every species, with no warning, from the moment it was written. Fixed
Session 125: switched to the v3 endpoint, added a required `key` param (read from the
`XC_API_KEY` env var), and rewrote the query to v3's tag-based syntax
(`gen:X sp:Y type:call`). Live-verified against real species. See
`TaxaLikely/CLAUDE.md`'s Known Footguns for the fix detail.

### RStudio's `dialogViewer()` can silently swallow a Shiny gadget's Done button when the gadget contains a `leaflet` map (found Session 134b)
`TaxaTools::define_search_polygon()` (a `miniUI`/`shiny` gadget with a `leaflet` map)
worked fine in earlier sessions but started returning `NULL` on every call in Session
134b, even when the user clicked **Done** (not Cancel) -- confirmed reproducible, not a
one-off. A *minimal* gadget (title bar + Done button, no leaflet) worked correctly with
`shiny::dialogViewer()` in the same RStudio session, ruling out a general
`shiny`/`miniUI` problem. The *exact* production gadget code worked correctly when its
viewer was swapped to `shiny::browserViewer()` (opens in a real browser) -- confirmed
both via the calling R session receiving the correct return value and via directly
inspecting the live page with Claude's Chrome browser-automation tools. `paneViewer()`
was then also tested directly against this exact gadget and confirmed working too.
Conclusion: on at least one real RStudio setup, the embedded `dialogViewer()` webview
specifically mishandles a gadget's Leaflet content in a way that breaks the Done
button's click-to-server round trip, while the identical gadget works fine via either
`browserViewer()` or `paneViewer()`. **If you write or modify any Shiny gadget in this
ecosystem that embeds a `leaflet` map, do not assume `dialogViewer()` works -- use
`shiny::paneViewer()` instead**, matching this ecosystem's existing mapping gadgets
(`TaxaTools::define_search_polygon()`, `TaxaHabitat::review_spatial_flags()`,
`TaxaExpect::plot_theta_map_interactive()` all use it, for one consistent
map-interaction style) -- and only use `dialogViewer()` if you've confirmed it
round-trips a real click on the actual machine you're targeting.
Also see this same debugging session's now-corrected R library documentation just above
(Developer Environment table) -- a stale-library-cache theory looked very plausible for
several rounds before being ruled out by directly checking `.libPaths()` from a real
session; don't skip that direct check next time something "should be fixed but isn't."
See `TaxaTools/CLAUDE.md`'s Session 134b note for the full multi-round debugging record.

---

## Recent Breaking Changes

Full history (Sessions 19–123) in `ecosystem_docs/NAME_CHANGE_HISTORY.md`. This table
holds only changes newer than that archive — trimmed to empty as of Session 124 (the
prior "Sessions 47+" table fully duplicated the archive, which had already grown to
cover the same range; see `ecosystem_docs/REENTRY_PROMPT_session124...` for the note).
Add new rows here as breaking changes land; archive + clear again once this grows long.

| Session | Change | Package | Notes |
|---|---|---|---|
| 125 | `audit_acoustic_coverage(xc_recordings = TRUE)` now returns real data | TaxaLikely | Behavioral, not signature. `.xc_recording_count()` migrated to Xeno-canto v3; requires `XC_API_KEY` env var (previously silently returned `NA` for every species regardless of key). |
| 125 | `correct_training_bias()` added | TaxaLikely | New preprocessing step, not yet called by any workflow. Divides classifier scores by an adaptive-shrinkage estimate of training-database representation bias before `unreferenced_candidates()`/`assign_scores()`. Overwrites `score_original` in place; raw value preserved in `score_uncorrected`. |
| 127 | `correct_training_bias(prior_weight = NULL)` → `correct_training_bias(tau = 1.0)` | TaxaLikely | Signature change. `prior_weight` param removed; `tau` added (single fixed global exponent, not adaptive per-candidate). Literature-grounded revision (Menon et al. 2020 logit adjustment) — see `TaxaLikely/CLAUDE.md`'s Session 127 note. Still not called by any workflow, so no downstream callers affected. |
| 136 | `fetch_reference_sequences()` → `fetch_ncbi_reference_sequences()` | TaxaLikely | Function rename. Old name didn't say NCBI anywhere; needed to disambiguate once a second live-API reference source (`fetch_bold_reference_sequences()`, BOLD Systems) existed. Old name kept as a deprecated forwarding alias (`.Deprecated()`, matches `audit_barcode_coverage_ncbi()`'s pattern) — all internal call sites (`build_site_reference()`, workflows, README, TaxaWizard snippets) updated to the new name directly. |
| 136 | `fetch_bold_reference_sequences()` added | TaxaLikely | New reference-fetch function, BOLD Systems analog of `fetch_ncbi_reference_sequences()`. Talks directly to BOLD's real v5 Data Portal API via `httr2` (no `bold` package dependency — that package targets BOLD's now-retired v3/v4 API and no longer works). Live-tested end to end. See `TaxaLikely/CLAUDE.md`'s Session 136 note. |
| 138 | `join_priors()` output is now site-preserving for multi-site observations | TaxaAssign | Behavioral, not signature. Final `distinct()` call now also keys on `grid_id`/`main_habitat` (bug fix — previously collapsed a multi-site observation to one row per candidate per its own best site). Any caller using `join_priors()`'s multi-site `site` data-frame path must now call the new `combine_multisite_priors()` before `compute_posterior()`. |
| 138 | `combine_multisite_priors()` added | TaxaAssign | New function, inserted between `join_priors()` and `compute_posterior()`. Combines per-site prior rows via precision-weighted logit combination. See `TaxaAssign/CLAUDE.md`'s Session 138 note. |
| 140 | `stack_occurrences()` now drops duplicate-`gbifID` rows | TaxaFetch | Behavioral, not signature. Rows with a duplicated non-`NA` `gbifID` are dropped (first kept) whenever that column is present. Defense-in-depth against double-counted GBIF records; sources without a `gbifID` column (literature/DataONE) are unaffected. See `TaxaFetch/CLAUDE.md`'s Session 140 note. |
| 140 | `fetch_occurrences_by_taxon()` added | TaxaFetch | New function. Taxon-centric batched GBIF fetch -- unions each candidate taxon's own search geometry and combines taxa sharing identical geometry into one `get_gbif_occurrences()` call. See `TaxaFetch/CLAUDE.md`'s Session 140 note. |
| 140 | `trim_to_amplicon()` added | TaxaLikely | New function. In-silico PCR: extracts the amplicon region from over-length reference sequences (e.g. full mitogenomes) via primer matching, instead of `build_sequence_matrix()`'s length filter discarding them outright. See `TaxaLikely/CLAUDE.md`'s Session 140 note. |
| 140 | `barcode_primer_defaults` / `resolve_barcode_primers()` added | TaxaTools | New registry + resolver, consumed by `TaxaLikely::trim_to_amplicon()`. Populated only with verified MiFish-U/E (12S) primers so far. See `TaxaTools/CLAUDE.md`'s Session 140 note. |
| 141 | `barcode_primer_defaults` gains 6 more entries (16S, COI, cytb, rbcL, matK, trnL) | TaxaTools | Behavioral, not signature. Every mito/chloroplast marker in `barcode_length_defaults` now has a verified primer pair; nuclear markers (18S/ITS/ITS2) deliberately still unpopulated. See `TaxaTools/CLAUDE.md`'s Session 141 note. |
| 142 | `barcode_primer_defaults` gains `coi-leray`; bare `"COI"` now ambiguous | TaxaTools | Behavioral, not signature. The real eDNA COI mini-barcode (mlCOIintF/dgHCO2198) is now registered alongside `coi-folmer`. Any existing caller passing bare `barcode_term = "COI"` to `resolve_barcode_primers()`/`trim_to_amplicon()` must now specify `"COI-Folmer"` or `"COI-Leray"` explicitly -- bare `"COI"` now errors instead of resolving. See `TaxaTools/CLAUDE.md`'s Session 142 note. |
| 143 | `join_priors(backbone_id = ...)` added, no default | TaxaAssign | New required parameter (errors if omitted). Replaces a previously hardcoded, un-overridable `backbone_id = 4L` inside `join_priors()`'s taxonomy-fallback fill (`R/join_priors.R`). No safe default exists -- the correct backbone depends on which backbone the caller's input taxonomy was verified against, which varies by project. All in-repo call sites updated to pass it explicitly. |
| 143 | `posterior_consensus(backbone_id = 11L)` default removed | TaxaAssign | Signature change: default changed from `11L` to `NULL`. Errors only when `lookup_missing_taxonomy = TRUE` and `backbone_id` is not supplied (lazy validation -- most call sites never touch this path and are unaffected). |
| 143 | `run_bayesian_pipeline(backbone_id = 4L)` default removed | TaxaAssign | Signature change: `backbone_id` is now required, no default (errors immediately if omitted). Previously defaulted to `4L` (NCBI) although the parameter is forwarded unconditionally into `join_priors()`/`posterior_consensus()` -- there is no backbone choice that is safe for every project. All in-repo call sites updated to pass it explicitly. |
| 143 | `run_llm_pipeline(backbone_id = 4L)` default removed | TaxaAssign | Same change as `run_bayesian_pipeline()` above, same reasoning. All in-repo call sites updated to pass it explicitly. |
| 146 | `assign_taxa_llm(taxa_per_call = 30L)` → `15L` | TaxaAssign | Behavioral default change. Lowered after confirming a real batch of 30 taxa truncated 4/5 times at `call_api()`'s default `max_tokens = 3000`, silently falling back to uniform priors. Matches `TaxaFlag::review_assignments()`'s own independently-made `30L → 15L` fix for the identical failure mode. |
| 146 | `run_llm_pipeline(taxa_per_call = 30L)` → `15L` | TaxaAssign | Same change, forwarded to `assign_taxa_llm()`. |
| 146 | `.parse_taxa_response()` gives a truncation-specific warning | TaxaAssign | Behavioral, not signature. When the LLM response has no closing `]` at all (truncation signature), the warning now names the real cause and two concrete fixes instead of the old generic "failed to parse" message. |
| 147 | `score_consensus(rank_thresholds = NULL)` → `c(species=98, genus=95, family=90, order=85)` | TaxaAssign | Signature + behavioral change. A caller relying on the old default silently got zero score-based species-vs-congener discrimination -- see `TaxaAssign/CLAUDE.md`'s Session 147 note for the ROC-sweep evidence. Pass `rank_thresholds = NULL` explicitly to restore old behavior. Auto-rescaled by /100 if `score_col` looks like a 0-1 proportion scale. Verified against every real call site and test; none broken (539/539 tests unchanged). |
