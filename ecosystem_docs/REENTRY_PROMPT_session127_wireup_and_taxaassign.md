# Re-entry Prompt — Session 127: Logit-Adjustment Revision Done, Wire-Up Still Open, TaxaAssign Likely Next

**Status:** All three TaxaMatch/TaxaLikely data-type Layer-1 mini-chains (image,
acoustic, sequence) now exist and are live-tested (image/acoustic: Session 124;
sequence: Session 126). This session did NOT touch those scripts. Instead it revised
`TaxaLikely::correct_training_bias()` — added Session 125, still unwired — after the
user questioned its design before trusting it near any real workflow. Read
`TaxaLikely/CLAUDE.md`'s Session 127 note first for the full literature-research
rationale and the exact formula change; this file is the concrete next-steps agenda.

---

## What changed this session (quick reference)

`correct_training_bias(scored_df, count_col, score_col = "score_original", tau = 1.0)`
— **signature changed**, `prior_weight` param removed, `tau` param added.

- Old (Session 125): `tau_i = n_i/(n_i+prior_weight)` — adaptive, different per
  candidate, self-referential (`prior_weight` defaulted to the candidate set's own
  median count). Empirically behaved like a step function pivoting at the median —
  demonstrated mathematically this session to make the lower-n candidate win almost
  regardless of which one was actually correct, whenever two candidates' raw n
  differed by much.
- New (Session 127): `tau` is a single **fixed global scalar** (default `1.0`),
  applied identically to every candidate — matches Menon et al. 2020's "logit
  adjustment" (ICLR 2021, arXiv:2007.07314), the standard theoretically-grounded
  correction for exactly this situation (post-hoc correction of a pretrained
  classifier's output using known/estimated class frequencies, no retraining).
  `score / n^tau` structure kept unchanged — proportionally equivalent to Menon's
  `pi^tau` form within one observation's candidate set (the `N_total` normalizing
  constant cancels), so no global training-count total needs to be known.
- Missing/zero counts still fall through to the uncorrected score (deliberate,
  documented deviation from strict logit adjustment — practical necessity, not
  literature-supported).
- Open, unresolved caveat (confirmed by the literature research, not fixed by it):
  `n_i` here is a noisy **external proxy** (public iNaturalist/Xeno-canto counts),
  not the classifier's actual internal training count — no paper directly studies
  how much the Fisher-consistency guarantee degrades under that gap. `tau` is
  exposed, not hardcoded, for this reason.
- Tests fully rewritten (27 expectations), `devtools::check()`: 0/0/0.

---

## Next-Session Plan

### 1. Wire `correct_training_bias()` into the image/acoustic Layer-1 workflow (still the actual next step from Session 124/125's original plan)

This is now TWO sessions overdue relative to the original Session 124 reentry plan —
both the Session 125 design and this session's revision happened *before* ever running
the function near real data. Concretely:

- **Image**: insert into `TaxaMatch/inst/workflows/score_image_workflow.R`'s output,
  right after loading the checkpoint, before `unreferenced_candidates()`:
  ```r
  taxamatch_image_match_obj <- TaxaLikely::correct_training_bias(
    taxamatch_image_match_obj, count_col = "n_observations"
  )
  ```
  `score_image_inat()`'s output already carries `n_observations` per candidate (no
  extra API call). Re-run the real 6-photo camera-trap tutorial (Session 124) and
  compare top-1 accuracy and per-photo winner before/after correction, using the
  `tau = 1.0` default first.
- **Acoustic**: still needs the join that never got built —
  `audit_acoustic_coverage(xc_recordings = TRUE)`'s census `n_recordings` onto the
  BirdNET match object by taxon (Session 125's reentry prompt spelled out the exact
  merge; nothing has changed there). Confirm the real column names in
  `read_birdnet_output()` + `create_taxon_names()`'s output before assuming
  `taxon_name` is the join key.
- **This is now finally a good time to run the grounding-truth check the user
  originally proposed** (bucket real labeled observations by
  `log10(n_true / n_best_wrong_competitor)`, compare accuracy with/without correction
  per bucket) — the 6-photo image set and 3-sandpiper acoustic set are still small for
  this, so treat it as a first look, not a final calibration. If it flags problems,
  that's the point at which to reconsider `tau` empirically (Menon et al.'s own tuned
  optimum was NOT 1 in their setting — no reason to assume 1 is right here either
  without checking).
- Update `TaxaMatch/CLAUDE.md`'s and `TaxaLikely/CLAUDE.md`'s workflow-script table
  entries once wired in, same as any other function addition to a workflow chain.

### 2. TaxaAssign — the user's suspected next major area, and a reasonable one

All three Layer-1 mini-chains (image, acoustic, sequence) currently stop deliberately
at the likelihood object — each one's own header comment says why: continuing to
TaxaAssign would need real occurrence-based priors (via TaxaExpect) for the *specific*
species each tutorial actually uses (5 camera-trap mammals, 3 Calidris sandpipers, 5+
real PtConception fish), which none of the three has built yet. That is the concrete,
well-scoped shape "move on to TaxaAssign" would take:

- Build real `TaxaExpect` priors for at least one of the three species sets (the
  camera-trap mammals are probably easiest — GBIF occurrence data for 5 well-known
  North American mammals near a known real site, 34.41°N/-119.86°W, should be
  straightforward to fetch).
- Feed the resulting likelihood object + priors into
  `TaxaAssign::compute_posterior()` / `compute_posteriors_workflow.R` (already exists
  and is tested as part of the five-package Gadus/GBIF chain — this would be a NEW
  real-species run through that same existing machinery, not new TaxaAssign code).
- **Loose end worth checking early**: `TaxaID/CLAUDE.md`'s ecosystem table still marks
  TaxaAssign's status as "Planned," but Session 123's notes already describe testing
  `compute_posterior()`, `posterior_consensus()`, `join_priors()`, `add_slash_taxon()`
  live as part of the five-package chain. That status label is very likely just stale
  — worth a quick look and correction, not a sign TaxaAssign doesn't exist yet.

### 3. Stage 3 items from Session 124's reentry prompt — now partly unblocked, still not started

Carried forward unchanged, see `REENTRY_PROMPT_session124_image_acoustic_workflows.md`
for full detail:

- **Real head-data testing** (WorkflowTest, Mugu, PtConception 12S/18S) — was blocked
  on the sequence pathway existing; Session 126 built it, so this is now unblocked.
  Small `head()`-sized subsets of real match/occurrence tables, testing shape, not
  full production re-runs.
- **Function-promotion candidates** — `fill_higher_ranks()` + `species <- taxon_name`
  pattern, still at 4 real sites (Session 126's sequence scripts didn't add a 5th —
  `blast_sequences()` already returns full family/genus/species columns via NCBI
  taxonomy resolution, so neither new script needed the pattern). Still below the
  promotion bar; no new information.
- **Layer-2 wrapper decisions** — unresolved, no new information.
- **Drive cleanup check** — `TaxaMatch/inst/extdata/` untracked bird photos
  (Google-Drive multi-parent-file concern, [[feedback_google_drive_multiparent_files]]
  in memory). Check whether the user has unlinked the Drive folder yet before doing
  anything with those files yourself.

---

## Process notes for next session

- Per `TaxaID/CLAUDE.md`: always ask before editing multiple existing files at once
  (this was violated once already, Session 125 — see that reentry prompt's closing
  note). This session batched several `.md` edits under the user's explicit
  "act independently... file saving is approved" grant — that grant was scoped to
  this session's specific stated tasks; don't assume it carries forward automatically
  without the user re-confirming at the next session's start.
- If wiring `correct_training_bias()` into a real workflow moves `tau` away from the
  `1.0` default based on what real data shows, update this function's own roxygen
  docs (the "Open caveat" section) to record what was found — that section currently
  describes the caveat as unresolved, and should stop saying that once it's actually
  been checked against real labeled data.
