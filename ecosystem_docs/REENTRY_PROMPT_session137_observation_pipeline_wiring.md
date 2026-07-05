# Reentry Prompt: Wiring the Single/Multi/Grouped-Observation Pipeline

**Status: planning only, nothing implemented yet.** Written 2026-07-05 (Session 137),
branch `single-observation-pipeline`, after a full survey of workflow scripts and the
Session 134/134b/134c spatial-grouping design work. Read this first when re-entering
this effort — it supersedes nothing already committed, it sequences what's left.

---

## The one-paragraph version

The spatial-grouping *mechanism* (`TaxaMatch::build_site_table()`,
`group_observations_by_bbox()`, `assign_spatial_group()`,
`TaxaAssign::update_prior_from_consensus(spatial_group_map=)`) is real, tested, and
live-verified — but it is wired into **zero** of the four production workflow scripts.
Meanwhile, the "escalation ladder" (broaden genus → family → order when a singleton's
own genus has no reference data or occurrence records) has been validated by hand three
separate times (Sessions 134, 134b, 134c all say the same thing) but **still does not
exist as a callable function anywhere in the ecosystem.** That absence is the actual
bottleneck blocking both the single-observation case and the spatially-independent
multi-observation case from working end-to-end — clustered multi-observation already
works today via the existing community-level `build_priors()`/`train_biodiversity_model()`
machinery, once spatial grouping is actually wired in.

---

## What's confirmed done (don't redo this)

- `TaxaExpect`'s five `habitat_col = NULL` functions — committed, prior session.
- `TaxaMatch::build_site_table()` — unifies `observation_id`/`lat`/`lon`/
  `spatial_group_id`/`spatial_group_N` across image/DNA/acoustic pathways; defaults to
  singleton groups from creation.
- `TaxaMatch::group_observations_by_bbox()` + `assign_spatial_group()` — interactive and
  manual spatial grouping, last-drawn-wins overlap, live-verified including the
  `dialogViewer()`/leaflet gadget bug fix (now a documented ecosystem-wide footgun).
- `TaxaTools::define_search_polygon()` — shared gadget, moved from TaxaFetch, generalized
  for both search-area and spatial-group drawing.
- `TaxaAssign::update_prior_from_consensus(spatial_group_map=)` — **already correctly
  skips single-observation groups** (`table(spatial_group_map$spatial_group_id) >= 2L`
  eligibility check). Confirmed via direct source read (`TaxaAssign/R/update_prior_from_consensus.R`
  lines 61-70, 118-176) and exercised in `ecosystem_docs/explore_spatial_grouping_session134b.R`
  §7. Default `NULL` preserves old behavior. **No further work needed on this function.**
- Naming settled permanently: `spatial_group_id`/`spatial_group_map`, eligibility always
  by counting membership, never by id-string pattern.

## What's confirmed NOT done

- **The escalation ladder is not a function.** Grepping "escalat" across
  TaxaLikely/TaxaExpect/TaxaMatch/TaxaAssign Function Inventories returns zero hits for
  an actual implementation — every hit is a reference to the still-needed work. This is
  the single largest piece of new engineering in this whole effort.
- **No production workflow calls `build_site_table()`/`group_observations_by_bbox()`/
  references `spatial_group_id` at all** (confirmed via grep across all four scripts
  below). The mechanism and the workflows have never been connected.
- **Acoustic pathway has zero site metadata**, same gap as the already-flagged
  DNA/BLAST "Reads-table relocation" item — `read_birdnet_output()` carries no
  GPS/site columns, so `build_site_table()`'s required externally-supplied `site_df`
  has no real source for either pathway yet.

---

## Sequenced phases

### Phase 1 — Escalation ladder as a real, reusable function

**Recommended package placement (confirm before starting): `TaxaTools`.** The
hierarchy-walking logic itself (given a taxon at rank X with no usable data, what's the
next coarser rank's name?) is generic taxonomic utility, not fetch-API-specific —
matches the precedent of `%||%` and `define_search_polygon()` already living in
TaxaTools as shared, non-duplicated logic. Each consuming package (TaxaLikely for
reference-sequence fetch, TaxaExpect for occurrence fetch) does its own retry loop
calling this function, rather than one function owning the whole retry-and-refetch
flow across two different downstream APIs.

Design sketch (confirm/adjust with the user before implementing):
```r
TaxaTools::escalate_taxonomic_rank(taxon_name, current_rank, rank_system,
                                    max_levels = 2L)
# returns the taxon name at the next coarser rank in rank_system, or NA if
# current_rank is already the coarsest rank available / max_levels exhausted
```
Validate against the same real cases already used for ad hoc validation (Sessions 134):
PtConception 12S queries (*Rhacochilus toxotes*, *Embiotoca caryi*) and the bobcat-photo
GBIF case. Do not re-derive the validation from scratch — the prior sessions' notes
(`TaxaLikely/CLAUDE.md`, `TaxaExpect/CLAUDE.md` Session 134 notes) already have the
real species names and expected broadened ranks.

### Phase 2 — Wire spatial grouping into `TaxaID_Workflow_Template_TEST.R`

This is the master template (741 lines, 8 sections: BLAST → TaxaFlag contamination →
TaxaFetch occurrences → TaxaHabitat → TaxaExpect priors → TaxaLikely → TaxaAssign →
TaxaFlag review) and currently hardwires **one** `STUDY_LAT`/`STUDY_LON`/`STUDY_RADIUS`
and **one** `SITE_GRID_ID` for the entire run. Its own trailing "NOTES FOR ADAPTING"
block already admits multi-site isn't solved.

Concrete change: insert `build_site_table()` → `group_observations_by_bbox()` right
after Section 2's contamination-filtered table, producing real `spatial_group_id`
values. Branch Sections 3-5 (occurrence fetch → priors) per group: pooled fetch for
`spatial_group_N >= 2` groups (existing `build_priors()`-style machinery, no new code),
escalation-ladder fetch (Phase 1's function) for `spatial_group_N == 1` groups. Section
7 (`join_priors()`/`compute_posterior()`) needs `TaxaAssign::update_prior_from_consensus(
spatial_group_map = ...)` passed through explicitly (the function already handles it
correctly, per "confirmed done" above — this is just wiring the call site).

### Phase 3 — Wire `score_image_workflow.R`

Smallest lift. Currently applies one hardcoded `SITE_LAT`/`SITE_LNG` to every photo in
the CONFIG section, even though `score_image_inat()` already supports per-photo
EXIF-derived coordinates. Change: stop overriding per-photo EXIF with one global
site pair (or make the override explicitly opt-in for genuinely single-site batches),
then call `build_site_table()` on the checkpointed output before handing off to
TaxaLikely.

### Phase 4 — Reads-table relocation (sequence AND acoustic)

**Needs your input before implementation**, not just engineering: the real sample-label
convention (how does a DNA sample ID or a BirdNET recording filename actually encode
site/time?) was never confirmed with the user in prior sessions — this was explicitly
deferred each time it came up (134, 134b). Once confirmed, build the function(s) that
produce a real `site_df` for `build_site_table()` from:
- The sequence/Reads-table pathway (currently ad hoc `pivot_longer()` in
  `TaxaFlag/inst/contaminant_workflow.R`, extracts `event_id` only, no place/time
  parsing) — likely relocates to TaxaMatch.
- The acoustic pathway (`read_birdnet_output()`/`score_acoustic_workflow.R`) — same
  shape of gap, not previously tracked as its own item; treat as the same underlying
  problem (site metadata living in a filename/manifest convention that needs parsing
  into `site_df`), not a separate design question.

### Phase 5 — TaxaAssign `(observation_id, site)` schema question

Only matters once Phase 4 produces real multi-site ASVs (a sequence genuinely detected
at more than one real site in one sequencing run). Decide whether `join_priors()`/
`compute_posterior()`/`posterior_consensus()` need to key on the `(observation_id, site)`
pair rather than `observation_id` alone. Explicitly deferred in every prior session
pending Phase 4 — "probably deserving its own session" per the 134b reentry prompt.

### Phase 6 — Test matrix

The three scenarios, run end-to-end through the Phase-2-updated template (or a smaller
harness if the full template is too heavy to iterate on):
1. **Single observation** — one isolated record, no others to pool with. Must resolve
   via the escalation ladder on both the likelihood side (reference fetch) and the
   prior side (occurrence fetch), never via the shared community model.
2. **One clustered group** — multiple observations at different exact coordinates but
   sharing one bounding box. Must resolve via the existing pooled
   `build_priors()`/`train_biodiversity_model()` path, `spatial_group_N >= 2`.
3. **Multiple independent groups (mixed)** — some observations cluster into one or more
   real groups, others remain singletons in the same batch. Confirms
   `group_observations_by_bbox()`'s automatic grouping correctly splits the batch and
   that Phase 2's branching logic routes each group through the right path
   simultaneously, not just one path at a time in isolation.

None of these three have been run through a real workflow end-to-end yet — 
`explore_spatial_grouping_session134b.R` exercises the grouping *mechanism* on synthetic
data, but never through an actual likelihood→prior→posterior run.

### Phase 7 — Documentation

Vignette "Step 1.5" fork writeup, README pointer, `ECOSYSTEM_WORKFLOW.md` mechanics
section, TaxaFetch vignette cross-reference. Deliberately last, per every prior
session's own explicit deferral ("documentation... deliberately deferred until the
mechanics are real").

---

## Open questions to resolve before/during implementation

1. **Escalation ladder package placement** — TaxaTools recommended above; confirm.
2. **Reads-table sample-label convention** (Phase 4) — genuinely needs the user's
   real-world answer, not an engineering guess.
3. **Search-area-vs-spatial-group reconciliation** — `group_col` support exists in
   `define_search_polygon()`, but no per-group fetch-search-area drawing workflow has
   been built. Unclear if this blocks Phase 2 or can be deferred further; assess once
   Phase 2 is underway.
4. **Likelihood-model-registry / prior-cache question** — unresolved since before
   Session 134: is a registry keyed by marker+family/order (or species+grid_id) still
   useful once automatic grouping exists, or does grouping supersede it? Never decided
   either way; worth a deliberate call before Phase 2 goes very far, since it would
   change how much gets rebuilt per group vs. cached.

## Not in scope for this effort

`TaxaLikely/inst/workflows/image_acoustic_likelihood_workflow.R` needs no changes — it
operates purely at the per-observation-id candidate-scoring level, upstream of any
spatial-grouping decision, and is already data-type/observation-count-agnostic by
construction.

## Related reading, don't re-derive

- `ecosystem_docs/REENTRY_PROMPT_session134_single_observation_pipeline.md`
- `ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`
- `ecosystem_docs/REENTRY_PROMPT_session134c_grouping_live_verified.md`
- `ecosystem_docs/explore_spatial_grouping_session134b.R` — working, live-verified
  demonstration of the grouping mechanism on synthetic data (7 observations, 2 real
  clusters + 2 outliers) — the closest thing to a Phase 6 test that already exists,
  though it never runs a real likelihood→prior→posterior pipeline.
- `~/.claude/projects/-Users-lafferty/memory/project_single_observation_pipeline_design.md`
  and its linked memories (`project_clustered_vs_independent_reframe`,
  `project_site_table_contract_gap`, `project_temporal_predictor_todo`).
