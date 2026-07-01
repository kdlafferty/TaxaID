# Re-entry Prompt — Session 124: Image/Acoustic Layer-1 Workflows Done, Next Steps

**Status:** Item 4 of `REENTRY_PROMPT_session123_layer1_workflows.md` (image/acoustic
Layer-1 workflows) is DONE — live-tested, real data, 0 errors. Full record in
`ecosystem_docs/LAYER1_WORKFLOWS.md`'s "Image + acoustic scripts (Session 124)" section
— **read that first**, it has the complete bug list and design rationale.

Three new scripts, chainable in one R session:
```r
setwd("~/My Drive/Rscripts/projects/TaxaID")
source("TaxaMatch/inst/workflows/score_image_workflow.R")
source("TaxaMatch/inst/workflows/score_acoustic_workflow.R")
source("TaxaLikely/inst/workflows/image_acoustic_likelihood_workflow.R")
```

---

## Three-Stage Plan for Next Session

This is the actual prompt to work from. Do the stages in order; stop and reassess
context/scope between stages rather than pushing through all three in one sitting —
Stage 2 in particular is a multi-hour build on its own.

### Stage 1 — Xeno-canto access, then training-database bias correction

1. **Fix `TaxaLikely::.xc_recording_count()`** (`R/coverage.R`). It still calls the dead
   v2 endpoint (`https://xeno-canto.org/api/2/recordings`, 404s unconditionally) — a
   leftover from Session 87's v2→v3 migration that this one function missed. Switch to
   `https://xeno-canto.org/api/3/recordings`, add a required `key` query param (register
   or reuse a key scoped to this specific use — see the key-provenance note in item 2
   below, don't silently grab whatever's in `~/.Renviron`), and rewrite the query from
   v2 free-text (`query = "{taxon} type:call"`) to v3 tag-based syntax
   (`query = "gen:{genus} sp:{species} type:call"`). `sources/birdnet_csv_export.py`'s
   `get_xc_recordings()` (Python, this session) is a working reference implementation of
   the v3 call shape. Full detail in item 2 below and `TaxaLikely/CLAUDE.md`'s Known
   Footguns.
2. **Design, then implement, the training-database bias correction** (item 6 below,
   raised after this file was first drafted). Discriminative classifiers (iNat CV,
   BirdNET) conflate true evidential weight with training-database species frequency —
   correcting for it means estimating R = n_i/n_j per candidate pair and dividing it out
   of the raw score ratio. Two estimators (count-based, labeled-reference geometric-mean)
   plus a symmetry-parameter diagnostic. Half the plumbing already exists (image
   `n_observations`, congener-borrowing for n_i=0 via `unreferenced_candidates()`) —
   the rest (acoustic counts, the labeled-reference estimator, the actual correction
   step, quality attenuation) is new. **Decide where the correction step lives**
   (new `assign_scores()` parameter vs. a new upstream preprocessing function) before
   writing code — this is a design discussion first, not a ticket to just start coding.

### Stage 2 — Sequence/BLAST Layer-1 workflows

Per the original three-way data-type split (`memory/project_workflow_redesign.md`),
TaxaMatch and TaxaLikely still need a sequence/BLAST Layer-1 script — the last of the
three data types (image and acoustic done in Stage-1-adjacent Session 124 work above).

1. TaxaMatch: `blast_sequences()` (already field-tested Session 115 on 5 real
   PtConception MiFish sequences, 5/5 100% hits) → a new
   `inst/workflows/blast_sequences_workflow.R`, matching the conventions of the other
   Layer-1 scripts (DEBUG_MODE tutorial data, explicit checkpoints, Output block).
2. TaxaLikely: the matching chain — `build_sequence_matrix()` → `train_likelihood_model()`
   → `evaluate_likelihoods()` — as a new `inst/workflows/` script. This is the ONE data
   type that actually needs the self-vs-non-self statistical model (bivariate normal
   over score+gap) — unlike image/acoustic, which use pre-trained classifiers and only
   a post-classifier calibration layer (`unreferenced_candidates()` + `assign_scores()`,
   confirmed this session — see item 7 below).
3. Live-test end to end, real data throughout — bigger build than image/acoustic (real
   BLAST calls, real DECIPHER alignment, real model training). Expect a debugging cycle
   at least as long as TaxaExpect's was in Session 123.

### Stage 3 — Additional items, if time/context allow

Not scoped tightly — pick these up only after Stages 1–2, and only as context permits.
Each is independent; none blocks the others.

1. **Real head-data testing** (WorkflowTest, Mugu, PtConception 12S/18S) — Session 123's
   deferred item 3, still pending. Now unblocked once Stage 2 exists (all four real test
   files are sequence/eDNA data, so this needs the sequence pathway, not image/acoustic).
   Small `head()`-sized subsets of real match/occurrence tables, testing *shape*, not
   full production re-runs.
2. **Function-promotion candidates** — evidence bar still not met (see item 5 below);
   check whether Stage 2's scripts add a third occurrence of the
   `fill_higher_ranks()` + `species <- taxon_name` pattern before promoting anything.
3. **Layer-2 wrapper decisions** — open question from Session 123 (does `build_priors()`
   still match `generate_priors_workflow.R`? does TaxaFlag's Session-63 rejected-wrapper
   precedent apply elsewhere?) — still unresolved, no new information this session.
4. **Drive cleanup check** — item 1 below; quick, non-blocking.

---

## Background / detailed notes (referenced above)

### 1. Loose end: TaxaMatch/inst/extdata/ still has untracked bird photos

Mid-session, `TaxaMatch/inst/extdata/` was found to already contain untracked copies of
Semipalmated/Western Sandpiper photos and CSVs from the user's manuscript folder
(Google Drive multi-parent-folder linking — same underlying file at two paths). These
are NOT the user's own photos to redistribute in this public package. Left in place
this session rather than deleted via `rm`, because deleting a multi-parented Drive file
through the desktop sync client risks trashing the object everywhere it appears
(including the user's actual manuscript folder), not just unlinking this one location.

**Next session:** check whether the user has removed that folder-location via Drive's
web/desktop UI yet. If so, the untracked files should be gone from
`TaxaMatch/inst/extdata/` on their own (confirm with `git status` / `find inst/extdata`)
— nothing to do. If not, remind them; do not `rm` it yourself.

### 2. .xc_recording_count() still calls a dead Xeno-canto v2 endpoint (NOT FIXED)

Found while building the acoustic workflow (see `TaxaLikely/CLAUDE.md`'s Known
Footguns, and `TaxaID/CLAUDE.md`'s Known R Footguns for the ecosystem-wide framing).
`TaxaLikely::.xc_recording_count()` (`R/coverage.R`) hits
`https://xeno-canto.org/api/2/recordings`, which now 404s unconditionally. This isn't
new breakage — `ecosystem_docs/NAME_CHANGE_HISTORY.md` records the v2→v3 migration as
already done in Session 87 (`fetch_reference_recordings()` updated then), but
`.xc_recording_count()` was added later, in Session 119, and was never brought in line
— it's been silently broken since the day it was written. Because the function checks
`resp_status != 200` and returns `NA_integer_` silently,
`audit_acoustic_coverage(xc_recordings = TRUE)` has always returned `NA` for every
species with no warning.

**Fix:** switch to `https://xeno-canto.org/api/3/recordings`, add a required `key`
query param, and rewrite the query construction from v2's free-text
(`query = "{taxon} type:call"`) to v3's tag-based syntax
(`query = "gen:{genus} sp:{species} type:call"`). Both changes were already validated
live while building `sources/birdnet_csv_export.py` this session — that script's
`get_xc_recordings()` is a working reference implementation of the v3 call shape,
though in Python, not R.

**Key provenance note:** Xeno-canto's docs (xeno-canto.org/explore/api) ask that each
application use its own registered key, not a personal one — the user registered/
confirmed a key specifically for this workflow. Whoever fixes `.xc_recording_count()`
should use the same reasoning (a key scoped to this specific use, not silently reusing
whatever's in `~/.Renviron`).

### 3. Sequence/BLAST Layer-1 scripts — see Stage 2 above

### 4. Real head-data testing — see Stage 3 above

### 5. Function-promotion candidates — one more data point, still below the promotion bar

Session 123's evidence-bar rule (`add_slash_taxon()`'s `consensus_OTU` was promoted only
after appearing identically in 3 independent real scripts) still applies. This session
added a second occurrence of a pattern first seen in Session 123's five scripts:

- **"Fill family/genus via `fill_higher_ranks()`, then `species <- taxon_name`"** —
  appeared identically in BOTH new Layer-1 scripts this session
  (`score_image_workflow.R`, `score_acoustic_workflow.R`), and is exactly the same shape
  as the earlier "derive `taxon_name` if missing" pattern flagged in Session 123's
  reentry prompt as appearing in TaxaHabitat's and TaxaExpect's scripts. Now 4 real
  sites total. Still recommend waiting for the sequence/BLAST scripts (Stage 2) to see
  if a *third* pattern (not just repetition of this one) recurs, before promoting
  anything — but this specific pattern is now closer to the promotion bar than anything
  else on the list.

### 6. Training-database bias correction for image/acoustic likelihoods — see Stage 1 above

Discriminative classifiers (iNat CV, BirdNET) conflate true evidential weight with
training-database species frequency: for a classifier trained on n_i examples of
species i, raw score_i ∝ true_likelihood_i × n_i. Uncorrected, `assign_scores()`
output is biased toward heavily-represented (common/well-photographed/well-recorded)
taxa. Correction: estimate R = n_i/n_j per candidate pair and divide it out of the raw
score ratio. Two estimators, complementary:

- **Count-based**: use published training counts directly. **Already free for
  images** — `score_image_inat()`'s own output already carries `n_observations` per
  candidate (from `taxon$observations_count`, no extra API call, Session 119) — the
  match object built by `score_image_workflow.R` this session already has this column.
  For acoustic, needs `audit_acoustic_coverage(xc_recordings = TRUE)`'s `n_recordings`
  — currently BROKEN (see item 2 above) — fixing that bug is a genuine prerequisite,
  not just cleanup.
- **Labeled-reference geometric-mean**: submit labeled images/recordings of known
  species with location/geo-filter suppressed (isolates pure vision/acoustic score,
  no geomodel prior), take the geometric mean of raw score ratios across both
  species' labeled sets — cancels the true-evidence term under a symmetry assumption.
  Nothing built for this yet in either package.
- Ratio of the two R estimates = symmetry parameter S, a diagnostic for how much two
  species differ in inherent visual/acoustic distinctiveness (or how badly the
  symmetry assumption fails for that pair). New, not built.
- **n_i = 0 (unreferenced species) is ALREADY HANDLED**: `unreferenced_candidates()`'s
  H2/H3 rows already anchor unreferenced species/genus placeholders at the
  best-scoring congener — exactly the "borrow from closely related referenced taxa"
  fallback this correction needs for the structural-exclusion case, and it's the same
  mechanism the sequence/eDNA path uses. No new work needed here.
- **Observation-quality attenuation** (a separate multiplicative term flattening
  likelihoods toward uniform as image/recording quality degrades) is entirely new —
  no analog in either package. NOT the same thing as the sequence path's `coverage`
  filter (that's a hard alignment-quality gate, not a continuous attenuation term).

**Not yet scoped as concrete implementation steps** — this is a design discussion to
pick up, not a ticket. Decide where the R-correction step actually lives (inside
`assign_scores()` as a new parameter? a new preprocessing function upstream of it?)
before writing any code.

### 7. Confirmed this session: image/acoustic use a post-classifier calibration layer, not a self-vs-non-self model

The DNA/BLAST pathway (`train_likelihood_model()`, `build_sequence_matrix()`) trains a
bivariate-normal model from a reference database's within-species ("self") vs.
between-species ("non-self") score distributions. Image/acoustic do NOT do this —
`unreferenced_candidates()` + `assign_scores()` take pre-trained classifiers' (iNat CV,
BirdNET) raw output and calibrate/normalize it (no training step). Confirmed by
grepping for any self/non-self language in TaxaLikely — none exists for image/acoustic.
This is why Stage 2 (sequence/BLAST) is architecturally the odd one out among the three
data types, not just the biggest build.

### 8. Trimmed this session: TaxaID/CLAUDE.md's Recent Breaking Changes table

The table had grown to duplicate `ecosystem_docs/NAME_CHANGE_HISTORY.md` for Sessions
47–123 (the archive's header comment said "Sessions 19–95" but it actually already
covered through 122 — the header was just stale). Appended the two un-archived Session
123 rows to the archive, updated its header, and trimmed the live table to empty
(ready for Session 124+ entries — none needed this session, since nothing here changed
an exported function's signature). If this recurs (the live table growing long again),
same fix: confirm against the archive's actual tail, migrate anything not yet there,
clear the live table.
