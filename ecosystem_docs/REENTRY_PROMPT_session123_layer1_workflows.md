# Re-entry Prompt — Session 123 Layer-1 Workflows: Next Steps

**Status:** Layer 1 built, verified, and live-tested for 5 of 8 packages (TaxaFetch,
TaxaHabitat, TaxaExpect, TaxaAssign, TaxaFlag). Full design/build/test record in
`ecosystem_docs/LAYER1_WORKFLOWS.md` — **read that file first**, it has the complete
list of scripts, conventions, bugs found, and the one ecosystem-wide footgun
(`.resolve_llm_fn()` silently degrading under fully-namespaced calls) that should
probably be added to `TaxaID/CLAUDE.md`'s Known R Footguns section if not done already.

This prompt covers four agreed next-steps items, in the order the user raised them.
None has been started — this is a planning/scoping document, not an implementation log.

---

## 1. Reappearing code snippets → candidate package functions

While building the five Layer-1 scripts, several small patterns were written more
than once **within the new scripts themselves** (not just in the old bespoke
PtConception/Mugu scripts audited earlier this project). Candidates, roughly in order
of how much duplication/risk they've already shown:

- **"Derive `taxon_name` if missing via `create_taxon_names()`"** — appears identically
  in TaxaHabitat's and TaxaExpect's scripts, patching the same TaxaFetch-output gap
  (Variant A never produces `taxon_name`). Worth asking: should `TaxaFetch::stack_occurrences()`
  or `filter_gbif_quality()` just add `taxon_name` itself, closing the gap at the
  source instead of patching it at every consumer?
- **"Dynamic focal grid_id/habitat derivation from a priors-shaped object"** — appears
  in TaxaExpect's script (`SITE_GRID_ID`/`SITE_HABITAT` from `taxaexpect_priors` or
  `sites`) and again, nearly identically, in TaxaAssign's and TaxaFlag's scripts
  (re-deriving `SITE_HABITAT` from `taxaexpect_priors` a second and third time). A
  small helper (e.g. `TaxaExpect::infer_focal_site(taxaexpect_priors)`) returning both
  values with the length-1 guard already written three times would remove real
  duplication — this is a stronger candidate than most, since it's now been
  independently re-written 3x with identical guard logic.
- **"Adaptive optional-term formula assembly with a graceful skip"** — the Moran-basis
  and `main_habitat`-fixed-effect conditional-inclusion pattern in TaxaExpect's script
  (`c(if (...) "term")` vector assembly) is specific to that one script for now, but if
  TaxaLikely's Layer-1 script(s) end up building GLMM-style formulas too, watch for
  this recurring.
- **The synthetic-likelihood-object builder in TaxaAssign's script** (`.build_obs()`)
  is currently one-off and tutorial-only — not a strong candidate for promotion since
  it exists specifically to fill the TaxaMatch/TaxaLikely gap and should disappear once
  those scripts exist (see item 4).

**Suggested approach for next session:** don't promote anything speculatively. Wait
until either (a) TaxaMatch/TaxaLikely's scripts are built and reveal whether these
patterns recur a third/fourth time, or (b) the item 3 real-data testing below surfaces
the same gaps against real PtConception/Mugu-shaped data. Promotion should follow the
same evidence bar already used this session (`add_slash_taxon()`'s `consensus_OTU`
addition was promoted only after it showed up identically in 3 independent real
scripts) — not "this looks reusable," but "this has already been rewritten more than
once."

---

## 2. Layer-2 wrappers — should these workflows become wrapper functions?

Partially already true: `run_bayesian_pipeline()`, `run_llm_pipeline()` (TaxaAssign),
and `build_priors()` (TaxaExpect, spanning TaxaFetch+TaxaHabitat+TaxaExpect) already
exist as Layer-2-shaped wrappers, predating this session's Layer-1 work. Open questions
for next session, not yet decided:

- **Does each new Layer-1 script map 1:1 onto an existing wrapper, or is there a gap?**
  Concretely: does `build_priors()`'s internal call sequence still match what
  `generate_priors_workflow.R` now does (adaptive Moran-basis skip, adaptive
  `main_habitat` term, species-breadth pre-flight check)? If `build_priors()` predates
  those fixes, it may have the same live bugs the Layer-1 script had before this
  session's debugging — worth checking before assuming the wrapper is already correct.
- **TaxaFetch has no standalone wrapper.** Nothing currently collapses
  `fetch_occurrences_workflow.R`'s GBIF two-path dispatch + quality filter into one
  call outside of `build_priors()`'s larger scope. Worth a small
  `TaxaFetch::fetch_and_filter_occurrences()`-style wrapper, or intentionally leaving
  it granular since it's only ~3 real function calls already.
- **TaxaAssign's new VARIANT B (LLM pathway) and TaxaFlag have no wrapper at all** for
  the specific sequence built this session (`review_assignments()` →
  `add_posthoc_assessment()`). Given TaxaFlag's own docs note `combine_flags()` was
  deliberately dropped in Session 63 ("a wrapper that guesses parameters is more
  frustrating than helpful") — this may be a case where the granular Layer-1 script
  actually IS the right level of abstraction, not a wrapper candidate. Worth deciding
  explicitly rather than defaulting to "add a wrapper for consistency."
- **Recommended first step:** before writing any new wrapper, diff `build_priors()`
  against `generate_priors_workflow.R` line by line to see how stale it already is —
  this determines whether "make a wrapper" or "fix the existing wrapper" is the actual
  task.

---

## 3. Test the workflows against real head-data (WorkflowTest, Mugu, 12S, 18S)

Everything tested so far uses **synthetic tutorial data** (genus *Gadus*/family
Gadidae, North Atlantic, GBIF-fetched fresh each run). It has never been run against
the ecosystem's own real, messy data. Candidates, all previously read/analyzed earlier
in this project (see memory: bespoke-script analysis of these same four files):

- `TaxaID/inst/TaxaID_Workflow_Template_TEST.R` — has a tiny embedded 3-sequence ASV
  fixture already designed for exactly this kind of quick test.
- `Rscripts/eDNA/SepulvedaMugu/MuguFishWorkflow.R` — multi-marker (12S/COI/16S), real
  BLAST output on disk (`MuguWilderFish_blast_match_*.rds` etc. — some may need
  regenerating since stale coverage caches were deleted this session).
- `Rscripts/eDNA/PtConception/PtConceptionWorkflow_12S.R` — narrow marker, real data.
- `Rscripts/eDNA/PtConception/PtConceptionWorkflow_18S_2.R` — broad marker, real data,
  the one with SILVA+NCBI dual-reference and sampling-group logic.

**Approach to scope this sensibly:** "head data" suggests small subsets (e.g. `head()`
of the real match/occurrence tables) rather than full production-scale runs — the goal
is verifying the new Layer-1 scripts' *shape* holds up against real, non-tutorial data
structures (real column quirks, real multi-marker structure, real SILVA/NCBI backbone
collisions), not re-running full analyses. This is also the first real opportunity to
exercise the sampling_group / broad-marker VARIANT B paths in TaxaFetch/TaxaHabitat/
TaxaExpect that the Gadus tutorial (single narrow genus) never touched.

**Do this after item 4's TaxaMatch/TaxaLikely scripts exist**, if practical — otherwise
this real-data testing will hit the same "no TaxaMatch/TaxaLikely Layer-1 script" gap
that TaxaAssign's synthetic-likelihood workaround was built to route around, except
this time with real data that deserves a real answer, not another synthetic bootstrap.

---

## 4. Explore workflows for images and acoustics (TaxaMatch/TaxaLikely)

The largest deferred item. Per the original redesign plan (`memory/project_workflow_redesign.md`):

- **TaxaMatch** needs separate Layer-1 workflows per data type: BLAST/eDNA (sequence),
  iNaturalist CV (image), BirdNET (acoustic). `TaxaMatch::score_image_inat()` (image)
  and existing BLAST functions are already built; acoustic ingestion functions'
  current state should be re-checked before scoping this.
- **TaxaLikely** needs the same three-way split for score→likelihood conversion. The
  package's own docs already note acoustic/image use a different sub-path than eDNA
  (`unreferenced_candidates()` + `assign_scores()`, no reference-matrix training step —
  classifiers are pre-trained, TaxaLikely acts as a post-classifier calibration layer
  only). This is a smaller lift than the sequence path, which needs the full
  `build_sequence_matrix()`/DECIPHER/`train_likelihood_model()` chain.

**Suggested starting point:** the image/acoustic path is structurally simpler (no
DECIPHER alignment, no reference database fetch) than sequence/BLAST — likely the
faster of the two to build and test live, and would close the "TaxaAssign has no real
likelihood input" gap for at least one data type sooner. Sequence/BLAST is the higher-
value target long-term (it's what all four real-data test files in item 3 actually use)
but is a bigger build: real BLAST calls, real DECIPHER alignment, real model training —
expect a debugging cycle at least as long as TaxaExpect's was in this session.

**Before starting either:** re-read `TaxaMatch/CLAUDE.md` and `TaxaLikely/CLAUDE.md`
fresh — both have had real changes (Session 119's `score_image_inat()`, the
`unreferenced_candidates()`/`assign_scores()` unified pipeline from Session 99) that
predate this session's work and haven't been re-verified against current source the
way every function called in the five completed scripts was.

---

## Suggested order for next session

Given the four items build on each other:

1. Quick pass: confirm the llm_fn footgun note landed in `TaxaID/CLAUDE.md` (item 0,
   should already be done — check before re-doing it).
2. Item 4 first (image/acoustic TaxaMatch/TaxaLikely) — this unblocks a REAL likelihood
   object, which makes item 3's real-data testing meaningful without another synthetic
   bootstrap, and directly extends the working chain rather than leaving it a dead end.
3. Item 3 (real head-data testing) once a real TaxaMatch/TaxaLikely path exists for at
   least one data type.
4. Item 1 (function promotion) and item 2 (wrapper decisions) as they naturally surface
   during items 3–4 — both are explicitly "wait for evidence" items, not standalone
   tasks to schedule first.
