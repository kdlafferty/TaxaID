# Re-entry Prompt — Session 134 Single-Observation Pipeline

**Status:** Three real bugs found and fixed in `TaxaExpect` (tested, verified against real data, ready to commit). Architecture design for the broader single-observation/independent-vs-clustered pipeline is largely converged but NOT implemented — this prompt is for starting that implementation.

---

## Git branch: `single-observation-pipeline`

All work described here happened on, and should continue on, the **`single-observation-pipeline`** branch, NOT `main`.

**At the start of the next session**, confirm you are on the right branch:
```
! git -C "~/My Drive/Rscripts/projects/TaxaID" branch
```
You should see `* single-observation-pipeline`. If not:
```
! git -C "~/My Drive/Rscripts/projects/TaxaID" checkout single-observation-pipeline
```

If another chat is also working in this same folder on something unrelated, check branch state before committing anything — branch checkouts are shared across all sessions pointed at this directory (see [[feedback_git_branches]] memory).

---

## Context summary — read these memory files first

This session covered a lot of ground across two distinct threads. Read in this order:

1. `~/.claude/projects/-Users-lafferty/memory/project_single_observation_pipeline_design.md` — **index/overview, read this first.**
2. `~/.claude/projects/-Users-lafferty/memory/project_clustered_vs_independent_reframe.md` — the core architectural reframe (bbx-based grouping, not a user-declared category).
3. `~/.claude/projects/-Users-lafferty/memory/project_site_table_contract_gap.md` — the site-table prerequisite.
4. `~/.claude/projects/-Users-lafferty/memory/project_temporal_predictor_todo.md` — deferred, but touches the same site-table work.
5. `~/.claude/projects/-Users-lafferty/memory/project_taxaflag_domestic_species_floor_note.md` — smaller, separate deferred item.
6. `TaxaExpect/CLAUDE.md`'s session notes (search for "habitat_col = NULL" and "theta_epsilon") — the detailed record of what was actually implemented and verified.

---

## Thread 1: Already implemented, tested, and verified — ready to commit

Three real bugs in `TaxaExpect`, found while testing whether the community-level prior pipeline could run on a narrow, broadened, single-observation-style occurrence fetch:

1. **`habitat_col` hardcoded/required** in `prepare_model_dataframe()`, `train_biodiversity_model()`, `generate_undetected_diversity()`, `generate_full_priors()`, and `optimize_grid_size()`. All five now support `habitat_col = NULL` as a genuine opt-out (not a placeholder constant, which would still crash `train_biodiversity_model()`'s Tier 2 GLMM fit on a single-level factor).
2. **`theta_epsilon`'s singleton-mirror auto-raise** (Session 108) was clipping every tier's predictions, not just Tier 2 — silently flattening real Tier 1 differentiation whenever many candidate species had genuinely low individual probabilities (exactly what a broadened, realistic candidate pool produces). Fixed by scoping the raised floor to Tier 2 only.
3. **`optimize_grid_size()`** had its own separate, unconditional `habitat_col` requirement (different code path than the above — a descriptive grouping/counting function, not a model fit, so it never had the Tier-2-crash failure mode, but still needed the same `NULL` convention for consistency). Fixed.

All three verified end-to-end against real data (a real bobcat camera-trap photo's candidate species, GBIF-fetched at order-Carnivora broadening) — `optimize_grid_size(habitat_col = NULL)` -> `create_sites_from_grid()` -> `prepare_model_dataframe(habitat_col = NULL)` -> `train_biodiversity_model(habitat_col = NULL)` -> `generate_undetected_diversity()` -> `generate_full_priors()`, no workarounds, Tier 2 fits, priors correctly differentiated in rank order matching real detection counts. `devtools::test()`: 383 passing, 0 failing. `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**This session ends by committing this work.** If you're reading this in a fresh session and it's already committed, skip to Thread 2.

---

## Thread 2: Architecture design, converged but not implemented

### The core reframe

Clustered vs. independent observations is not a user-declared category — it's a geometric property of whether observations' coordinates fall within a shared bounding box ("bbx", not "radius" — the project's preferred term). Two unrelated citizen-science photos from the same park are "clustered" in the sense that matters even if collection was totally uncoordinated.

**Decided: go with automatic grouping**, not a declared single/clustered/independent fork. Concretely:
- Plot all observations' site coordinates on a map.
- Let the user draw one or more bounding-box polygons over the plot to define groups (reusing `TaxaFetch::define_search_polygon()`, an EXISTING Shiny/Leaflet gadget from Session 111 that already supports arbitrary draggable-corner polygons — it just doesn't currently overlay any data points on the map. Needs: (a) an observation-points-overlay parameter, (b) a wrapper that calls it in a loop to collect multiple polygons/groups, since it currently returns one polygon per call).
- Each observation gets a `group_id` (parallel naming to the existing `grid_id`) based on which drawn box (if any) contains it.
- **Points outside every drawn box are dropped from consideration, with a clear alert to the user** (not silently, and not auto-assigned to a singleton fallback group — the user is expected to draw a box for anything they want analyzed).
- Fetch bbx must be >= the grouping bbx (can extend further for more regional context, never smaller).
- `grid_id` (existing, fine-grained, one modeling location) is unaffected by any of this — a group is coarser and can span many grid cells, exactly like the existing clustered pipeline already does.

### What grouping actually determines (not two pipelines, one fetch-scoping decision)

Automatic grouping does NOT require two different pipelines. It only decides how broad the occurrence/reference fetch needs to be before handing off to the SAME already-fixed statistical machinery (Thread 1's fixes apply either way):
- **Priors**: grouped observations pool candidate species and share one bbx occurrence fetch (existing clustered design). A post-grouping singleton fetches for just its own candidates, broadened taxonomically (genus -> family -> order) instead of spatially (validated empirically this session on real GBIF data, see [[project_single_observation_pipeline_design]] for the numbers).
- **Likelihoods**: grouped observations pool candidates for reference-fetching before training `train_likelihood_model()` (validated on real PtConception 12S queries). A post-grouping singleton escalates rank for just its own candidates, or falls back to `assign_scores(score_type = "similarity_softmax")` as a last resort (confirmed weaker-discriminating than a trained model, not equivalent).
- **Minimum group viability**: no new size threshold — rely on the existing Tier 1/Tier 2/singleton-mirror/fallback-A-B-C machinery to degrade gracefully, same as it already does for sparse regional data.

### The site-table prerequisite (blocks grouping entirely until resolved)

Automatic grouping needs every observation's coordinates before the fork decision. Currently inconsistent across data types (confirmed directly in source):
- Image (`score_image_inat()`): HAS per-observation `lat`/`lng` (from EXIF or override).
- DNA/BLAST (`standardize_match_data()`): does NOT have per-observation site info.
- Acoustic (`read_birdnet_output()`): does NOT have per-observation site info either -- **not discussed this session, needs its own investigation** (what site metadata does BirdNET-Analyzer output carry, if any?).

**Proposed fix**: a single, unified LONG-FORMAT site table across all data types -- one row per `(observation_id, place, time)`, not one row per `observation_id`. This is necessary, not just a stylistic choice, because of a real complication:

### The ASV multi-site complication (sequence data only, but shapes the whole site-table design)

A sequence ASV (`observation_id` for the DNA pathway) is identified by sequence content across an entire multi-sample sequencing run -- the same ASV can have non-zero reads in several sample columns, meaning the same organism was genuinely detected at multiple physical sites. This is fundamentally different from image/acoustic, where one `observation_id` is inherently one capture event, one place, one time.

**Consequence, confirmed by the user as a real bug in current workflows, not just an architectural gap**: existing workflows compute one likelihood per ASV (correctly location-independent) and join it against ONE workflow-global site, silently assuming that single site applies to every observation -- when some ASVs were actually detected at several different real sites. The fix: `(observation_id, site)` becomes the true analysis unit for priors/posteriors -- same likelihood row, reused across however many real sites that ASV was detected at.

**Data source for this, already exists**: a "Reads" table (rows = `observation_id`/ASV, columns = sample labels each carrying an associated place AND time), currently read into `TaxaFlag`'s contaminant-detection step. User's proposal: relocate this parsing logic to `TaxaMatch`, running BEFORE the bbx/grouping step (contaminant filtering as a side benefit of doing this early -- simplifies the match object). `flag_contaminant()` itself can stay in `TaxaFlag` or move; either way this is mostly a workflow-wiring change, not new engineering, since the Reads-table parsing logic already exists.

**Decided**: single unified long-format site table for all data types (not a special case per pathway) -- the user confirmed "a single format would seem simpler," with the caveat that we need to confirm the actual means of generating it for sequence data (likely already partially present in the existing `flag_contaminant()`/Reads-table logic -- verify this directly before assuming).

### Downstream consequence not yet designed in detail

If `(observation_id, site)` becomes the real analysis unit for sequence data, `TaxaAssign::join_priors()` / `compute_posterior()` / `posterior_consensus()` all currently key on `observation_id` alone as "one observation = one set of competing hypotheses." Extending this to `(observation_id, site)` for sequence data is a real schema question that was flagged but NOT resolved this session -- needs its own careful design pass before implementation, probably its own session.

### `update_prior_from_consensus()` -- skip for single/independent

This TaxaAssign function boosts priors for species confirmed present in OTHER samples, with an explicit circularity guard ("a sample's own posterior never feeds its own prior"). Valid ONLY when other samples share your local species pool -- i.e., multiple-clustered observations. Must be skipped entirely for single observations (no other samples exist) and multiple-independent observations (other samples' confirmed presence tells you nothing about an unrelated location) -- applying it there would smuggle in a false shared-context assumption.

### Documentation placement (discussed, not written)

The fork belongs at the seam between "have `match_df`" (end of TaxaMatch) and "fetch priors/likelihoods" (TaxaFetch/TaxaLikely) -- not owned by either package narratively. Proposed placement:
- `TaxaAssign/vignettes/taxaid-ecosystem.Rmd`: a new "Step 1.5" in the existing linear walkthrough, right after "Step 1: Standardize match data (TaxaMatch)" and before "Step 2/3" -- next to the existing `### Two Pathways` section (an orthogonal fork: Bayesian vs. LLM pathway), not nested under it. Include concrete example archetypes (single observation / multiple-clustered / multiple-independent), each mapped to a decision cue and the concrete functions/params involved.
- `README.md`'s "Pipeline Overview": brief pointer paragraph only, not the full explanation.
- `ecosystem_docs/ECOSYSTEM_WORKFLOW.md`: the technical/developer-facing mechanics (site-table contract, `group_id`, escalation ladder) -- this file already has an "Open Design Issues" section with an unresolved, directly-related item ("sample_meta not generated by any workflow") that this work resolves.
- A cross-reference pointer at the top of `TaxaFetch`'s own vignette (first package whose actual function calls differ based on the fork).
- Eventually, a new Layer-1-style workflow script demonstrating the automatic-grouping path end to end.

### Loose thread not yet reconciled

Earlier in this session (before the automatic-grouping decision), a "likelihood-model registry" and "prior cache" design was discussed in detail (keyed by marker+family/order for likelihoods, species+grid_id for priors) to support efficient reuse across independent observations. This was NOT explicitly reconciled with the automatic-grouping framework decided later -- worth revisiting whether the registry idea still applies (e.g., caching a broadened-fetch model per post-grouping singleton's taxonomic scope) or whether grouping supersedes the need for it. Flag this explicitly in the next session rather than assuming either way.

---

## Suggested implementation order for the next session

1. Confirm Thread 1's fixes are committed (check `git log`); if not, do that first.
2. Site table: design the long-format schema, build the image-pathway extraction (simplest, data already present), then investigate acoustic (open question) and sequence (relocate Reads-table logic from TaxaFlag to TaxaMatch).
3. `define_search_polygon()`: add points-overlay parameter; build the multi-group wrapper loop.
4. Fetch-scope branching: wire group_id into occurrence/reference fetch calls (pool within group, escalate/broaden for post-grouping singletons).
5. Skip `update_prior_from_consensus()` for non-clustered groups.
6. Only THEN tackle the `(observation_id, site)` TaxaAssign schema question (step 2 above may surface information that changes how this should be designed) -- probably deserves its own session given the depth flagged above.
7. Documentation, last, once the mechanics are real and can be described accurately rather than speculatively.
