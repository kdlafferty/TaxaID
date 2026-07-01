# TaxaID Layer-1 Workflows — Design, Build Log, and Test Record

**Status:** 7 of 8 packages now have at least one Layer-1 script. Five-package sequence
chain complete (TaxaFetch, TaxaHabitat, TaxaExpect, TaxaAssign, TaxaFlag). TaxaMatch and
TaxaLikely gained image + acoustic data-type scripts in Session 124; sequence/BLAST
Layer-1 scripts for TaxaMatch/TaxaLikely remain deferred (see Deferred Work below).
**Last updated:** 2026-07-01 (Session 124)

---

## What this is

Part of a broader redesign of TaxaID's workflow scripts into three layers (full design
in `memory/project_workflow_redesign.md`):

- **Layer 1** — package-level teaching workflows in each package's own `inst/workflows/`.
  This document covers Layer 1 only.
- **Layer 2** — wrapper functions collapsing each Layer-1 script into one call (some
  already exist: `run_bayesian_pipeline()`, `run_llm_pipeline()`, `build_priors()`).
- **Layer 3** — a combined ecosystem-level script calling Layer-2 wrappers in sequence.

Layer 1's audience is someone learning a package step by step. Each script is meant
to be `source()`-able top to bottom with real data and no private lab files.

---

## The five scripts

| Package | File | Purpose |
|---|---|---|
| TaxaFetch | `TaxaFetch/inst/workflows/fetch_occurrences_workflow.R` | Resolve taxa → GBIF keys → fetch occurrences → quality-filter → stack |
| TaxaHabitat | `TaxaHabitat/inst/workflows/assign_habitat_workflow.R` | LLM habitat classification → assign to points → spatial QAQC |
| TaxaExpect | `TaxaExpect/inst/workflows/generate_priors_workflow.R` | Grid occurrences → fit biodiversity GLMM → generate priors |
| TaxaAssign | `TaxaAssign/inst/workflows/compute_posteriors_workflow.R` | Join likelihoods to priors → compute posteriors → consensus |
| TaxaFlag | `TaxaFlag/inst/workflows/flag_detections_workflow.R` | LLM plausibility review + post-hoc tier assessment |

All five chain together via `tempdir()` checkpoints under the prefix `tutorial_gadus`
(genus *Gadus*, North Atlantic — TaxaFetch's built-in tutorial example). Running all
five in **one R session**, in order, reproduces the full pipeline end to end:

```r
setwd("~/My Drive/Rscripts/projects/TaxaID")
source("TaxaFetch/inst/workflows/fetch_occurrences_workflow.R")
source("TaxaHabitat/inst/workflows/assign_habitat_workflow.R")
source("TaxaExpect/inst/workflows/generate_priors_workflow.R")
source("TaxaAssign/inst/workflows/compute_posteriors_workflow.R")
source("TaxaFlag/inst/workflows/flag_detections_workflow.R")
```

**Important:** `tempdir()` is scoped to one R session. Running the five scripts as
separate `Rscript` invocations (rather than `source()`-ing them in one session) breaks
the checkpoint hand-off — each process gets its own temp directory.

---

## Design conventions established this series

- **Fully namespaced calls** (`Package::function()`) throughout — never bare `library()`.
  This was deliberate but has one real consequence: see "Known footgun" below.
- **`DEBUG_MODE <- TRUE`** default: runs a small, real, built-in tutorial example.
  `DEBUG_MODE <- FALSE` has a `>>> SWAP IN YOUR OWN DATA <<<` block for real studies.
- **Explicit-only checkpoints**: `saveRDS()` + a `message()` with the exact `readRDS()`
  line to paste next session. No `file.exists()`-gated auto-reload branches anywhere —
  this was a direct response to feedback that automatic caching had become an
  "if_else explosion" that was hard to track and caused wasted re-runs.
- **VARIANT A / VARIANT B** convention for genuinely different call sequences (narrow
  vs. broad marker in TaxaFetch/TaxaExpect; Bayesian vs. LLM-shortcut in TaxaAssign).
  The inactive variant is either fully commented-out code or a documented-but-not-run
  section, depending on whether building it live was in scope.
- **"Real continuity, synthetic bootstrap where needed"**: when a script needs data
  from a package with no Layer-1 script yet (TaxaMatch/TaxaLikely), it builds a small,
  clearly-labeled synthetic object using **real species names already produced upstream**
  — never fully-fabricated data unconnected to anything real. TaxaFlag's Step 1/2 need
  no synthetic data at all (100% real continuity); TaxaAssign's likelihood/match objects
  are synthetic-but-real-species; TaxaFlag's `flag_contaminant()` is the one function
  documented-but-not-run, because it needs lab read-count data with no natural
  connection to anything in this GBIF-occurrence-based chain.
- **Every script's Output block documents the exact column contract** for the next
  package to consume — this is the interface documentation, not just a comment.

---

## Test methodology

Every script was drafted by an agent, then personally verified against the actual
package source (not just `CLAUDE.md` prose) before being run, then **live-tested
against real GBIF data, real LLM calls, and a real fitted model** by actually executing
it — reading the code was not treated as sufficient. This caught real bugs in every
single script; none would have been found by static review alone (see Bugs Found below).

**Last full-chain confirmation run:** 2026-07-01, Session 123. All five scripts run in
one R session (1.3 min elapsed), real GBIF fetch (genus *Gadus* → 498 occurrence rows,
then family Gadidae fallback in TaxaExpect → 297 rows / 9 distinct species), real
Anthropic LLM calls (TaxaHabitat classification, TaxaAssign LLM pathway, TaxaFlag
review), real GEBCO bathymetry download, real glmmTMB model fit (`taxaexpect_priors`:
9 rows, 8 Tier 1 species + 1 global-floor proxy).

**Result: 0 errors.** Terminal object `taxaassign_consensus_flagged`: 3 rows (one per
synthetic observation), 26 columns, with sensible values — `habitat_plausibility =
"likely"` (correct: Gadidae are marine), `geographic_plausibility = "possible"` (correctly
hedged given the tutorial's honest non-geocoded placeholder), `posthoc_assessment =
"vague_rank"` (correct: consensus only resolved to family rank).

---

## Bugs found and fixed (by actually running the code)

This list is here because every one of these represents a class of bug that static
reading missed — useful if the same pattern recurs when TaxaMatch/TaxaLikely are built.

### TaxaExpect (`generate_priors_workflow.R`)
1. Hardcoded `k = 10L` in `compute_moran_basis()` crashed on sparse grids (k must be
   < the number of distinct grid cells). Fixed: adaptive `k`.
2. Even adaptive `k` could still fail ("no positive eigenvalues") on poorly-connected
   cells. Fixed: wrapped in `tryCatch()`, degrades gracefully (drops spatial terms).
3. `paste0()` on a zero-length vector does **not** produce zero elements — it recycles
   the zero-length arg as `""` against length-1 siblings. This silently built a formula
   term referencing a literal, nonexistent column `B`. Fixed: vector-based term assembly
   (`c(if (...) "term")`), correct by construction instead of string-surgery.
4. The tutorial's single-genus checkpoint has only 1 species — TaxaExpect's model needs
   *co-occurring* species to estimate relative abundance at all. Fixed: added a
   species-breadth pre-flight check (not just a location-count one) before trusting a
   checkpoint, falling back to a broader live fetch (family Gadidae) otherwise.
5. A single, constant `main_habitat` value (from the tutorial-only habitat-tagging
   shortcut) can't be fit as a model factor (R's contrasts need ≥2 levels). Fixed: made
   the `main_habitat` term conditional on actually having ≥2 levels.
6. `screen_spatial_formula()`'s `recommended_formula` is documented as a **character
   string**, not a formula object — passing it straight to `train_biodiversity_model()`
   errored. Fixed: added the missing `as.formula()` conversion.

### TaxaAssign (`compute_posteriors_workflow.R`)
7. `generate_full_priors()`'s own roxygen docs (which I'd read but hadn't passed to the
   drafting agent) state its output lacks `taxon_name_rank`, which `join_priors()`
   requires. Fixed: derive it directly (every modelled row is species-rank by
   construction).
8. `posterior_consensus()` requires `hypothesis_type`, normally added by
   `TaxaLikely::evaluate_likelihoods()` — absent for hand-built synthetic data. Fixed:
   added `"specific_candidate"` to every synthetic row (all are real, named species).
9. **Not a workflow bug — a stale install.** `add_slash_taxon()` came back with 15
   columns instead of 17 (missing `consensus_OTU`/`primary_taxon`). The *installed*
   TaxaAssign package was pre-Session-123 — I'd edited the source earlier and told the
   user to reinstall, but never reinstalled it myself in this sandbox. Only the live
   test caught the gap. **Lesson: "I edited the source" ≠ "the running code reflects
   it" — reinstall before testing, every time, don't assume.**
10. `assign_taxa_llm()`'s default `llm_fn` silently degraded to uniform priors (no
    error at all) rather than calling the LLM — see the ecosystem-wide footgun below.
    Fixed: explicit `llm_fn` argument.

### TaxaFlag (`flag_detections_workflow.R`)
11. `review_assignments(irreducible_only = TRUE)` hard-errors if zero rows qualify.
    With only ~4 synthetic species shared across 3 tiny observations, non-irreducible
    candidate sets are the *expected* outcome for this small a pool (candidate sets
    routinely overlap), not bad luck. Fixed: check first, fall back to
    `irreducible_only = FALSE` when none qualify, with a clear message.

### Cross-script contract gaps
12. TaxaFetch's Variant A output has raw GBIF columns (`species`, `genus`, ...) but
    **no `taxon_name` column** — yet both TaxaHabitat's and TaxaExpect's scripts assumed
    it existed. Fixed in both: derive it via `TaxaTools::create_taxon_names()` if
    missing, rather than assuming the upstream script's shape.
13. `generate_full_priors()`'s `new_sites` parameter must be **site-level** (one row
    per grid_id × habitat, no `taxon_name`) — the draft passed the taxon-expanded
    `model_data` instead, which would have silently multiplied every site by however
    many taxa were originally observed there. Fixed: build `new_sites_focal` from the
    un-aggregated `sites` object instead.

---

## Ecosystem-wide footgun found (belongs in `TaxaID/CLAUDE.md`'s Known R Footguns)

**`.resolve_llm_fn()`'s default silently degrades instead of erroring, under
fully-namespaced calling conventions.**

`assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`, `suggest_unreferenced_species()`
(TaxaAssign) and `review_assignments()` (TaxaFlag) all default `llm_fn` to
`getOption("TaxaID.llm_fn", TaxaTools::call_api)`. `TaxaTools::call_api()`'s provider
auto-detection depends on `TaxaTools::.onAttach()` having run — which only happens via
`library(TaxaTools)`, never via `TaxaTools::function()`. Since this whole redesign's
house style is fully-namespaced calls only, that auto-detection path never fires, and
`call_api()` **silently falls back to uniform/degraded output** rather than raising an
error. This was caught only because a smoke test's output looked suspiciously uniform,
not because anything threw.

**Fix, everywhere this pattern is used:** pass `llm_fn` explicitly:
```r
llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
```
This resolves to a specific, working, namespaced function rather than the generic
dispatcher — exactly what TaxaHabitat's `build_habitat_prompt()`→`prompt_api()` call
already did correctly (it was the pattern everything else was checked against).

---

## Image + acoustic scripts (Session 124)

TaxaMatch and TaxaLikely needed multiple data-type variants per the original redesign
plan (BLAST/eDNA, iNaturalist image, BirdNET acoustic for TaxaMatch; sequence, image,
acoustic for TaxaLikely). Item 4 of `REENTRY_PROMPT_session123_layer1_workflows.md`
recommended starting with image/acoustic (no DECIPHER/reference-fetch step, simpler
than sequence/BLAST) — done this session, entirely with real data, no synthetic
bootstrapping:

| Package | File | Purpose |
|---|---|---|
| TaxaMatch | `inst/workflows/score_image_workflow.R` | Live `score_image_inat()` calls on bundled real camera-trap photos (5 mammal species, 4 families) |
| TaxaMatch | `inst/workflows/score_acoustic_workflow.R` | `read_birdnet_output()` on real BirdNET CSVs (3 confusable Calidris sandpipers) |
| TaxaLikely | `inst/workflows/image_acoustic_likelihood_workflow.R` | Two independent live sections consuming both checkpoints via `unreferenced_candidates()` + `assign_scores()` |

This is a **separate mini-chain** from the five-package Gadus/GBIF-occurrence chain
above — image/acoustic classification has no natural data connection to GBIF
occurrences, so it starts its own real-data story (camera-trap mammals /
confusable sandpiper calls) rather than bootstrapping something synthetic on top of
the Gadus chain. It stops at TaxaLikely's likelihood object — does not continue to
TaxaAssign/TaxaFlag (out of this task's scope; would need real occurrence-based priors
for these specific species, a separate task).

**Live-tested results:** image path 5/6 (83%) top-1 correct once the real camera site
lat/lng (34.41, -119.86) was supplied to `score_image_inat()` — 2 of 6 photos flipped
from wrong to correct vs. no location, since iNat's `combined_score` blends vision
confidence with local occurrence frequency. The one miss (coyote.JPG) is a genuine
name/geo-prior collision: top candidate was *Baccharis pilularis* ("coyote brush"), a
locally abundant plant. Acoustic path: 37/42 (88%) detection windows correct on real
BirdNET output; misses are genuine acoustic confusion between confusable congeners
(exactly what the user's original `birdnet_calidris_selftest.py` self-test was designed
to explore), not bugs.

**Bugs/gaps found by actually running these scripts:**
- `unreferenced_candidates()` needs ≥ 2 populated rank columns; both `score_image_inat()`
  and `read_birdnet_output()` only output `genus` (no `family`, no separate `species`
  column) — fixed via `TaxaTools::fill_higher_ranks()` + `species <- taxon_name` (full
  binomial; convention confirmed from `fill_higher_ranks()`'s own `@examples`).
- `read_birdnet_output()`'s output has no `taxon_name`/`taxon_name_rank` at all — same
  cross-script contract gap as Bug #12 below (TaxaFetch's missing `taxon_name`); fixed
  via `TaxaTools::create_taxon_names()`.
- `assign_scores(score_type = "probability")` errors/warns above 1.0 — correct for
  BirdNET's bounded 0-1 confidence, but wrong for iNat's UNBOUNDED `combined_score`
  (observed up to ~3000); needed `score_type = "similarity_softmax"` instead. Both
  score types ratio-normalize by the winning candidate's own score, so the winner's
  `score_likelihood` is always exactly 1.0 by construction — the meaningful comparison
  is which taxon won, not the magnitude.
- Xeno-canto's v2 API (used by the user's original self-test script) is fully removed
  (404) — v3 requires a key and tag-based query syntax (`gen:X sp:Y type:call`).
  **Also affects production code**: `TaxaLikely::.xc_recording_count()` still calls the
  dead v2 endpoint, so `audit_acoustic_coverage(xc_recordings = TRUE)` silently returns
  `NA` for every species. Not fixed (out of scope) — see `TaxaLikely/CLAUDE.md`'s Known
  Footguns.
- An earlier iteration of `score_image_workflow.R` used the user's own Semipalmated/
  Western Sandpiper photos from a personal manuscript folder — replaced with the
  camera-trap set after the user pointed out those specific photos (screenshots
  sourced from eBird/Macaulay-Library-linked checklists) weren't theirs to redistribute
  in this public package. Also found mid-session: `TaxaMatch/inst/extdata/` already had
  untracked copies of those bird photos via Google Drive multi-parent-folder linking —
  left in place (not deleted via `rm`, which risks trashing the same underlying Drive
  object everywhere it appears) pending the user unlinking that folder-location
  themselves via Drive's UI.
- Non-portable file names: bundling real photos under `inst/extdata/` triggered an
  R CMD check WARNING for directory names with spaces — fixed by renaming to
  `camera_trap_photos` (underscore).
- Stale local installs caught 2 unrelated latent issues while getting a clean
  `devtools::check()`: TaxaTools' installed copy predated the Session 122
  `is_plausible_binomial()` rename (broke TaxaLikely's `read_crabs_output()` tests);
  fixed by reinstalling TaxaTools. Not a code bug — same "reinstall before testing,
  don't assume" lesson as Bug #9 below.

---

## Deferred work

- **TaxaMatch and TaxaLikely still need a sequence/BLAST Layer-1 script.** Image and
  acoustic are done (Session 124, see above) — sequence/BLAST is the larger remaining
  lift (real BLAST calls, real DECIPHER alignment, real model training).
- **`TaxaFlag::flag_contaminant()`** is documented (full signature, algorithm, Flag
  Column Convention) but not run live — needs lab read-count data (sample × taxon,
  with blanks) that a GBIF-occurrence-based tutorial chain has no way to produce
  honestly.
- **Sampling-group classification** for broad-marker (18S/COI) workflows was confirmed
  reusable from TaxaHabitat's existing habitat-classification mechanism with **zero
  package changes needed** (see conversation record) — but not wired into any Layer-1
  script yet, since TaxaHabitat's tutorial data never needed it (narrow single-genus
  marker).
- See `ecosystem_docs/REENTRY_PROMPT_session123_layer1_workflows.md` for the concrete
  next-steps agenda.
