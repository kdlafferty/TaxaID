# Re-entry prompt — template work to do AFTER CaliforniaIntertidal is finished

**Written 2026-09-17.** Deliberately deferred work, not forgotten work. Everything here
was blocked on one fact: `CaliforniaIntertidal/CaliforniaIntertidalWorkflow_multi_marker.R`
is a scaffold with **31 explicit `## STUB` markers** and has never run, because it is
waiting on data (see `[[project_california_intertidal_multi_marker_2026_09_13]]` — the JV
methods changed twice, Illumina in Events 1-3 and Nanopore after, and the platform drives
the H1 score distribution at KS p < 2.2e-16).

It is the ONLY multi-stream workflow in flux. `MuguFishWorkflow.R` is the only one
running, and it is legacy (`MuguWilderFishWorkflow.R` was archived 2026-09-12).
Generalising a template from one scaffold plus one legacy script would bake in guesses,
which is why this waits.

## DO NOT START UNTIL

1. CalIntertidal has **actually run end to end** on real data, not just parsed. A
   workflow that has never run teaches nothing about which parts are essential.
2. Its `## STUB` count is **0**: `grep -c '## STUB' CaliforniaIntertidalWorkflow_multi_marker.R`
3. Its numbering has not drifted from what it is today (0-10, cross-marker work collapsed
   into Section 8) — item F below assumes it.

If (1) is true but (2) is not, read the remaining stubs first. A stub that survived a real
run is a design decision, not an omission.

## The state you are inheriting

The canonical template, `~/My Drive/Rscripts/eDNA/PtConception/TaxaID_eDNA_Workflow_Template.R`,
was brought fully current between 2026-09-15 and 2026-09-17 (eDNA commits `5b91fa4`,
`d77bc65`, `7e92325`, `798703b`, `b5bd27f`). It had been **unrunnable for two months** —
its Section 5 was the archived GLMM chain, plus three stale argument names and two silent
column/backbone drifts. It is now single-marker 0-10, kernel priors, full reference
screen, H1 calibration, evidence generators, report assembly, and a SUBSET/REUSE block.

**Nothing in it has been RUN.** It parses, both drift checks in
`diagnostics/workflow_checks/` are clean, the subset helper is unit-tested and was
exercised against real PtConception checkpoints — but its first genuine end-to-end run is
still ahead. Treat any claim about its behaviour as unverified until then.

## Task 1 — ratify or revise item F (cheap, do this first)

F was adopted 2026-09-17 as **documentation-only and PROVISIONAL**, on the user's own
condition that CalIntertidal might change it. The rule, in `CLAUDE.md`'s numbering-families
note: multi-stream workflows collapse the cross-stream trio into a single Section 8, so
Steps 9 and 10 mean TaxaFlag review and filter/output in every family; single-marker 0-10
stays canonical; `MuguFishWorkflow.R` (0-11) is a documented legacy outlier and is NOT
renumbered.

Decide whether the finished CalIntertidal still supports it. If its real run needed the
cross-stream stages separated again, F flips and Mugu becomes the standard instead — say
so explicitly rather than leaving two conventions undocumented, which is the state this
whole thread started from.

**A scope limit to keep honest rather than quietly drop.** F is stated data-type neutrally
(the axis is EVIDENCE STREAMS — marker for eDNA, classifier for image, detector for
acoustic) but the numbered-section convention barely reaches the non-sequence workflows:
`score_acoustic_workflow.R` has 2 numbered sections, `score_image_workflow.R` has 5, and
`image_acoustic_likelihood_workflow.R` has **none**. Neutral wording there is aspirational.
If you want it to be true, that is its own task — structure those three — and it is
bigger than it sounds.

## Task 2 — ONE template. Decided 2026-09-17. The question is now approachability.

**The user has decided: one template, with a multi-stream variant block.** Reason, in
their words: *"Just to get users started (not frightened)."* So Task 2 is no longer
"decide whether" — it is "add the variant without making the file hostile to a newcomer."

That decision is BETTER than the recommendation this document originally carried (which
was to document the pattern and build no template). It removes the exact failure this
whole thread came from: two coexisting templates, broadcast patches hitting one and
missing the other, both ending up unrunnable. One file means one set of patches. Do not
reopen that; the reasoning below is what replaces it.

**But it creates a real and opposite tension, which is the actual work here.** The
template is ~2,000 lines. "Comprehensive" and "not frightening" pull in opposite
directions, and a multi-stream variant makes it longer. Treat approachability as a
requirement of Task 2, not a nicety:

1. ~~**Add a QUICKSTART block at the very top**~~ **DONE 2026-09-17**, uncommitted. It
   replaced the old 17-line HOW TO USE header and names the must-edit settings by the
   `--- ... ---` heading they live under rather than by line number (the line numbers in
   this bullet had already drifted -- Section 0 is ~320 lines, not ~180). It also lists
   what to IGNORE on a first pass, the three environment variables (`ANTHROPIC_API_KEY`
   Steps 4/9, `ENTREZ_KEY` Step 7, `INAT_API_TOKEN` Step 8c) whose absence otherwise
   fails a run partway through rather than at the top, and points at SUBSET before a
   full run. All 24 cited variable names were verified to exist; +58/-10 lines, comments
   only, no logic touched; parses, and all three checks re-run clean on all seven files.
   **One real bug fixed in passing:** `STUDY_RADIUS`'s comment read `~330 km per degree`
   -- a porting slip from 12S single-site's correct `decimal degrees (~330 km)` for a
   radius of 3. Left alone it would have had a newcomer size their GBIF search polygon
   3x too large. Corrected in the template; the QUICKSTART agrees with it.
2. **Make the multi-stream variant a clearly-fenced block**, the way Variant A/B already
   is, so a single-marker user can see at a glance that it does not apply to them. The
   user's own condition was that it "can easily be scaled back to a single-marker".
3. **Do not let the variant duplicate the single-marker chain.** If the multi-stream path
   needs its own copy of Steps 6-8, that is two templates again wearing one filename, and
   the drift returns with the patches.
4. **Keep the strata and the abstraction data-type neutral.** The subset block already
   keys only on observation_id and candidate-set width, which works for sequences,
   acoustic detection windows and image detections alike. Name the axis EVIDENCE STREAM
   rather than "marker" in anything new -- the user asked for this specifically, noting
   the project's tendency to drift toward sequences.

**A newcomer's first run is where a latent break costs most.** On 2026-09-17 a single
real subset run found FOUR bugs in this template that neither parsing, nor the dead-call
sweep, nor the argument checker could reach -- including `flag_watch_candidates()`
rejecting the shipped `INVASIVE_TAXA <- character(0)` default, which would have stopped a
new user at Step 8g on their first attempt with nothing wrong in their own edits. Before
calling the multi-stream variant done, RUN IT, on a subset, using the mechanism in
Task 3. "Parses cleanly" has been wrong about this file four times.

## Task 3 — consider rolling the subset convention outward

The SUBSET/REUSE block is currently **template-only**, by explicit choice (2026-09-17) —
the six live workflows are untouched. See `diagnostics/workflow_checks/README.md` for the
two rules and the real-data baseline.

It is worth rolling into the live workflows once it has survived a real template run,
because testing is this project's biggest cost. Two workflows already have ancestors of
it: `PtConceptionWorkflow_12S_multi_site_FAST.R` has the two-prefix design and its own
`FAST_SUBSET`, and `MuguFishWorkflow.R` has `RERUN_FROM_STEP`. Reconcile rather than
layer — a second subset mechanism in the same file is worse than none.

**Both rules are load-bearing and neither is obvious:**
- RULE 1, a test run writes to its own `OUT_PREFIX` and only ever READS `REUSE_PREFIX`.
  Re-saving a shared upstream object bumps its mtime, the staleness gates key on mtime,
  and one such re-save cost a 2h47m recompute. Content-keyed `cache_dir` caches are the
  deliberate exception and SHOULD be shared.
- RULE 2, a subset exercises code paths and never produces numbers. The Good-Turing budget
  is quadratic in `f1`; the LOBO bandwidth, Empirical-Bayes `tau2`,
  `calibrate_query_noise()`'s confident-species floor, `compute_group_priors()`'s
  compositional `theta_sum` and `flag_contaminant()`'s read-count shrinkage are all
  whole-pool. The dangerous case is a NEGATIVE result, which is why subset status is
  STAMPED into checkpoints, exports and session metadata rather than printed.

## Open loose ends, each small and each real

- **`consensus_to_flagged`'s `from` is arguably incomplete.** `flag_watch_candidates()`
  takes the match object as well as the consensus, but that graph edge reads
  `from: ['consensus']`. Extending it adds a required input to a hand-audited edge and
  changes what TaxaWizard can generate, so it was left for its own decision
  (TaxaID `bc350bb`).
- **31 other graph functions are still uncovered.** The eight universal ones were placed
  2026-09-17; the rest are used by 3-4 of 5 workflows (the reference-screen chain, the
  report-assembly chain, the spatial-review trio, the evidence generators). Regenerate the
  list from `workflow_structure_outlines_2026_09_15.txt` rather than trusting it — it will
  have moved.
- **`.llm_fn_` in the template and in PtCon 12S both request `model = "claude-sonnet-4-6"`.**
  Not touched, because 12S ran successfully with it on 2026-09-14 so it evidently resolves
  in this environment — but it is not in the current Claude 5 model list, so check it
  before a long run rather than discovering it 40 minutes in.
- **A subset whose `SUBSET_ALWAYS_TAXA` names a common taxon crowds out the random
  stratum** — the sentinel took 175 of 365 observations (48%) on the real PtCon exercise.
  Working as designed; tune `SUBSET_N` or narrow the list.

## Run these before and after anything here

```bash
# from the TaxaID repository root
bash diagnostics/workflow_checks/check_dead_calls.sh <every live workflow>
Rscript diagnostics/workflow_checks/check_stale_arguments.R <every live workflow>
Rscript diagnostics/workflow_checks/test_subset_helper.R
```

Baseline 2026-09-17: all six production workflows and the template clean on both checks;
the subset helper passes ten properties.

## The lesson this whole thread exists to encode

A file that keeps receiving broadcast patches **looks maintained**. Both templates were
committed the same day as every running workflow, and both were dead. A patch to Sections
7-8 says nothing about whether Section 5 still runs.

And be suspicious of your own checker. The 2026-09-15 audit validated `Pkg::fun()` calls
against NAMESPACE but resolved bare calls only POSITIVELY, against the live export list —
so a bare call to an archived function vanished from the outline instead of being flagged.
It caught the template whose dead calls were namespaced and passed the one whose dead
calls were bare. A checker that can only confirm what exists cannot report what is missing.
