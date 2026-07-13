# Reentry Prompt: Pt Conception multi-site workflow migration (Task B)

**STATUS: written 2026-07-13 at the end of Session 153, before any Task B work started.**
Session 153 did a systematic comparison of all four real production workflow scripts
(`PtConceptionWorkflow_12S.R`, `PtConceptionWorkflow_18S_2.R`, `MuguFishWorkflow.R`,
`MuguWilderFishWorkflow.R` — all outside this monorepo, not under git, at
`~/My Drive/Rscripts/eDNA/PtConception/` and `~/My Drive/Rscripts/eDNA/SepulvedaMugu/`)
against `inst/TaxaID_Workflow_Template_TEST.R`, then split the fix into two tracks per the
user's direction:

- **Task A (done this session):** every template-alignment fix that does *not* depend on
  spatial/multi-site grouping, applied to all four workflows. See this repo's `CLAUDE.md`
  Session 153 note and `TaxaAssign/CLAUDE.md`'s Session 153 note for the full record
  (contaminant-filtering-never-applied bug fixed in all four; backbone-conversion ordering
  fixed in 18S_2 only, verified correct-as-is in 12S/both Mugu; reference-sequence fetch
  modernized to `fetch_ncbi_reference_sequences()` in all four; `ratio_threshold = 0` added
  where missing; a real empty-string-genus crash found and fixed in both the two
  PtConception workflows AND the template itself). The two Pt Conception workflows were
  renamed `PtConceptionWorkflow_12S_single_site.R` / `_18S_2_single_site.R` as part of this,
  since they get the multi-site sibling this document is about. The two Mugu workflows kept
  their names — no multi-site work is planned for them.
- **Task B (this document, not started):** build new `PtConceptionWorkflow_12S_multi_site.R`
  / `_18S_2_multi_site.R` files from the Task A `_single_site` baseline, porting the
  template's Sessions 137–139 spatial-grouping architecture. Explicitly **not** Mugu.

## Why this is worth doing now, not speculative future-proofing

Real, currently-unused multi-site data already exists. `Dangermond_Sample_Metadata2_
31Jan24.xlsx` (Barcode-keyed, at the same `DATA_DIR` the workflows already read from) gives
real coordinates for three named sites in the March 2021 run:

| Location | Samples | Approx. coords |
|---|---|---|
| BioD | 34 | 34.4425, -120.4535 (spans **10 distinct exact (lat,lon) pairs**, ~44m spread — see gotcha below) |
| Cojo | 2 | 34.4529, -120.4183 |
| Jalama | 2 | 34.5097, -120.5017 |

A second, finer-resolution file (`Dangermond_Sample_Metadata_29May24.xlsx`, SampleID-keyed)
splits further: BioD, Cojo inside cove, inside GovPt at fossil rock, Jalama, longterm
monitoring plots, Perkos inside bay, tap RO. Both the 12S March run (`JVB3105-MiFishU-*`)
and the 18S run (`JVB3105-18Sv9_89-*`) use the **same sample barcodes** (confirmed directly
— e.g. `Z7VT7NHJ`, `YNFHNXIA` appear as read-file sample columns in both), i.e. the same
physical filtered water, two markers sequenced from it — so one site table drives spatial
grouping for both marker workflows.

**Not covered**: the 12S August run (`JVB3506-*_JV270`) uses a different lab-plate barcode
scheme (`JV270_Plate_Layout.csv`, Jonah Barcode → plate position, not field coordinates); no
site-linking metadata for it was found in the same data directory. The user's framing:
more real coastal sites are coming later, and the point of this work is to exercise the
ecosystem's own spatial-grouping/escalation-ladder code against real data ahead of that,
not to get today's specific numbers exactly right. The template's own design already has a
graceful fallback for exactly this (an observation with no site-metadata match gets the
single hardcoded `STUDY_LAT`/`STUDY_LON` as its own site, never dropped) — don't block on
finding August site metadata; let it fall through.

## Template functions this migration uses (all confirmed to exist, signatures verified Session 153)

- `TaxaMatch::join_event_site_metadata(detections, site_metadata, event_col, id_col, control_samples)`
- `TaxaMatch::build_site_table(match_df, site_df, id_col)` — **default grouping is exact
  (lat,lon) match**, confirmed via `TaxaMatch/R/build_site_table.R`.
- `TaxaMatch::assign_spatial_group(sites, observation_ids, spatial_group_id, id_col)` — the
  **non-interactive** alternative to the gadget; requires `sites` already run through
  `build_site_table()`. **Use this, not `group_observations_by_bbox()`**, driven by the
  real `Location` labels above — necessary, not cosmetic, because BioD's 34 samples span
  10 distinct exact coordinates (see gotcha below), so the default exact-match grouping
  would fragment it into 10 near-duplicate groups instead of recognizing it as one site.
  Decide which of the two metadata files to standardize on — `reads_long$event_id` in both
  production scripts is already Barcode-keyed, so the 44-row Barcode file is the more
  direct fit; don't just grab the finer SampleID one because it looks more detailed.
- `TaxaMatch::group_observations_by_bbox(sites)` — the interactive gadget. Only relevant if
  you decide the known-Location approach above isn't sufficient (e.g. a real future site
  with no clean Location label).
- `TaxaFetch::fetch_occurrences_by_taxon(taxon_geometry_map, year_range, limit, ...)` —
  two-pass taxon-centric GBIF fetch, replaces both workflows' current single-pass
  family-key fetch.
- `TaxaTools::escalate_taxonomic_rank(taxon_name, current_rank, ...)` — genus→family→order
  escalation for zero-hit singleton candidates.
- `TaxaTools::define_search_polygon(...)` — **hard `stop()`s if `!interactive()`** (confirmed
  directly in `TaxaTools/R/define_search_polygon.R`); no batch fallback exists. This is the
  real blocker on fully automating Phase 3 below (see gotcha).
- `TaxaAssign::combine_multisite_priors()` — precision-weighted logit combination when one
  observation is genuinely detected at >1 site.
- `TaxaAssign::update_prior_from_consensus(spatial_group_map = site_table)` — restricts the
  confirmation-quantile boost to multi-member spatial groups only.

## Real gotchas found this session that change the shape of this work

A Plan-agent review (re-reading the template's actual Sections 2.5/3/5/7 source directly,
not trusting a summary) plus direct checks against the real metadata surfaced two things
that argue for landing this in phases rather than porting all four template sections at
once per file:

1. **The multi-member-group branch (template Section 3's Pass 1) keys on distinct *taxa*
   at a site, not distinct *samples*.** With real community diversity (dozens of ASVs per
   named site), BioD/Cojo/Jalama will almost certainly *all* land in the "multi-member"
   branch — which requires an interactive `define_search_polygon()` box-draw per group (no
   batch fallback, see above). Practically: you (the human) will need to run those specific
   box-drawing steps in RStudio; Claude Code cannot drive a live Shiny gadget. It also means
   the escalation ladder (one of the more interesting pieces to exercise) is gated to
   single-observation groups only and likely won't fire much on this real March data —
   worth knowing going in, not discovering after the port.
2. **18S_2's existing per-`sampling_group` loop (Section 5 in that file, a *taxonomic
   functional-group* axis — fish/phytoplankton/parasites/etc., Session 149's fix for a real
   shared-detection-effort bug) is a second grouping axis the template never has to
   reconcile.** Nesting spatial grouping inside it is the right direction (model fit stays
   once per sampling_group; only prior *generation* gains the spatial dimension), but a
   given site's resolved grid cell can differ *per sampling_group* (each group's own
   `.resolve_group_grid_id()`-style fallback fires independently on that group's own data
   sparsity) — so Section 7's `join_priors()` may need to run once per sampling_group
   rather than once globally. **Resolve this empirically, not by assumption**: check
   whether the fallback ever actually diverges across groups for the same real site before
   deciding a per-group `join_priors()` pass is needed.
3. **BioD's 34 samples span 10 distinct exact (lat,lon) pairs**, not one repeated
   coordinate (~44m spread — real GPS/visit-to-visit variation). `build_site_table()`'s
   *default* exact-coordinate grouping would fragment this into 10 near-duplicate groups.
   This is why `assign_spatial_group()` driven by the real `Location` column is called out
   above as necessary, not a style choice.

## Recommended sequencing (phased, each phase a checkpoint before the next)

Given the real taxon counts here, iterate against a **small subset of the match data
first** (a `TEST_MODE`/`SUBSET_N` flag limiting to a handful of genera/ASVs) so each phase
runs in seconds/minutes instead of waiting on full GBIF/LLM/model-fit calls; only switch to
the full dataset once the pipeline works end to end on the subset. Session 153's own
`evaluate_likelihoods()` verification runs took 15-20+ real minutes each on the full
13,463/10,390-query datasets — expect similarly long full-dataset runs here, and don't
block iteration on them.

1. **Plumbing only, one no-op spatial group.** Every observation in one group,
   `spatial_group_id`/`spatial_group_map` flowing through Sections 2.5/7 — must be provably
   identical to the `_single_site` baseline's output before doing anything real. Cheapest
   phase; do it on the subset.
2. **Real site metadata + `assign_spatial_group()` grouping.** Inspect the resulting
   `site_table` — group count, sizes, and roughly how many real ASVs are shared across
   >1 Location (this bears on how much `combine_multisite_priors()`/the confirmation-
   quantile boost will actually do — don't assume either way, count it) — **before**
   investing in Phase 3.
3. **Section 3 rewrite**: two-pass taxon-centric fetch + escalation ladder. Expect to
   personally run the interactive box-draws for each real multi-member group (per Phase
   2's count), on the subset first. Checkpoint the drawn WKT geometry itself (the template
   doesn't save this — a real gap worth fixing here, since re-running any later code
   change would otherwise force re-drawing every box).
4. **Section 5 rewrite**: per-spatial-group priors. 12S is a near-direct port (single
   grouping axis already). 18S_2 nests a spatial loop inside its existing per-
   `sampling_group` loop.
5. **Section 7 rewrite**: `combine_multisite_priors()` + real `update_prior_from_consensus
   (spatial_group_map = site_table)`. Resolve 18S_2's open grid-fallback-divergence
   question here (gotcha #2 above).

Full-dataset verification once the subset passes all five phases: spot-check a handful of
known species' priors/posteriors against the `_single_site` baseline's output for the same
taxa, confirming the per-group machinery produces *coherent* results, not just
error-free ones.

## Explicitly out of scope

- Multi-site work for either Mugu workflow.
- The 12S August run's own site metadata (none found) — falls through the existing
  single-observation-group fallback, unmodified.
- The backbone-conversion/reference-fetch/`ratio_threshold` items — already done, Task A,
  this session.
