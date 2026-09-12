# Re-entry prompt — What to check after the first full production runs since the reference-screen rewiring

**Written 2026-09-10.** The user is about to run full, real production workflows (live
NCBI/GBIF/LLM calls, hours per run) for the first time since a real architectural change
landed: `TaxaLikely::flag_reference_errors()`/`remove_flagged_references()`/
`TaxaMatch::verify_flagged_references()` were retired 2026-09-08, and reference-quality
screening moved upstream to `TaxaMatch::corroborate_references_locally()` ->
`evaluate_reference_accessions(local_corroboration=, skip_locally_corroborated=TRUE)` ->
`score_reference_labels()`. Four real production workflows were rewired the same day but
**deliberately never run live** (real NCBI cost, left for the user to trigger) --
`GreatLakes2023_ConsensusWorkflow.R`, `PtConceptionWorkflow_12S_single_site.R`,
`PtConceptionWorkflow_12S_multi_site.R`, `PtConceptionWorkflow_18S_2_single_site.R`. Both
Mugu scripts never used the old pattern and are unaffected. **This will be the very first
real execution of the new architecture against full-scale data.**

Read `TaxaLikely/CLAUDE.md`'s 2026-09-08 top session note (the retirement) and
`TaxaMatch/CLAUDE.md`'s 2026-09-03/04/05 notes (`corroborate_references_locally()`,
`evaluate_reference_accessions(local_corroboration=)`, `verify_removal_candidates()`,
`verify_local_corroborations()`, the KJ135626/MZ605481 false-rescue lesson) before
digging into any specific number below -- this doc assumes that context.

## Workflow additions, 2026-09-11 (all 6 production workflows + both templates; external files backed up `*.bak_pre_sentinels_log_audit`)

1. **Console log.** Each session writes `<OUT_PREFIX>_run_<timestamp>.log` in OUT_DIR:
   printed output is tee'd (`sink(split = TRUE)`), messages and warnings are copied
   by a `globalCallingHandlers()` handler so they still show in the console. Once per
   session; a re-run appends. Path recorded in the session metadata.
2. **`.save(habitat_lookup, "habitat_lookup")`** right after the cached lookup, so
   per-taxon habitat verdicts are a diffable checkpoint, not just cache files.
3. **Standalone, resumable training screen:** `inst/screen_training_references_
   standalone.R <GreatLakes|PtCon12S|PtCon18S> [max_hours]` runs Step 7a.11's exact
   call against the same cache dir, sleeping on NCBI's breaker, until every accession
   has a verdict; the next workflow run then serves the screen from cache. Run it
   overnight instead of letting the workflow grind. Mugu has no training screen.
4. **`session_meta$regression_sentinels`** (single-marker workflows) /
   `<OUT_PREFIX>_regression_sentinels.rds` (Mugu, which has no metadata block):
   training stats and floor, both screens' breaker flags and removal counts, the GBIF
   cache-fallback flag, the habitat cache summary, species-rank counts for the site's
   `SENTINEL_TAXA` (Section 0: GL grass carp/yellow perch/walleye; PtCon 12S *Girella
   nigricans*/*G. simplicidens*/*Fundulus parvipinnis*; Mugu the *Fundulus* pair; 18S
   none yet), and the console-log path.
5. **Automatic removal audit** after the match-candidate screen: when anything is
   actioned "remove", `verify_removal_candidates(screen_corroborators = TRUE)` runs on
   just those accessions (cache dir `*_audit_cache`, checkpoint `removal_audit`). A
   removal is overturned automatically ONLY if the audit ran (spared is NA on an NCBI
   timeout), it is spared on >= 3 corroborators or on 1-2 whose own labels read "keep"
   ("untested" does not count), and the LLM review did not call it a genuine mislabel
   -- the KJ135626/MZ605481 shape stays removed. PtCon 12S keeps `VETO_AUDIT_SPARED`
   alongside (Reduce(union, ...)); the audit should reproduce it and make it redundant.
6. **PtConception match objects** are built by each workflow's own Step 1
   `blast_sequences()` call behind a `match_obj.rds` checkpoint. Deleting that
   checkpoint forces a full re-BLAST (hours, NCBI) and the rebuilt object then carries
   `query_coverage` + the recorded floor, so `evaluate_likelihoods()`'s train/inference
   check works there too. Not done; a user decision on when to spend that.

## Run 2 outcome — GreatLakes, 2026-09-10/11 (finished 02:34, 244 min), first run on the coverage floor + habitat cache

**Completed end to end; PASSES the validation gate and beats the pre-drift baseline.**
Lamar, species level, matched samples (`REVIEW_formal_lamar_check.R`, outputs saved
as `*_run2_2026_09_11.rds`):

| | Run 1 (2026-09-10) | Validation arm C | **Run 2** | 2026-09-07 baseline |
|---|---|---|---|---|
| co-detections | 593 | 798 | **840** | 602 |
| ours-only | 144 | 177 | **141** | 104 |
| precision | 0.805 | 0.818 | **0.856** | 0.853 |
| recall vs Lamar species calls | 0.549 | 0.738 | **0.777** | 0.557 |
| unique species | 29/61 | 41/61 | **42/61** | 29/61 |
| overconfident | 1/1081 | 0 | **0** | 1/1081 |

- Species-rank observations 543 -> 694; 64 distinct consensus taxa; final CSV 870 rows /
  59 taxa (46 in the 2026-09-04 baseline). Grass carp at species rank in 5 ASVs, reviewed
  possible/possible/likely/low, valid, in the CSV. *Perca flavescens* 78 obs unchanged.
- Training: `min_pair_coverage 0.8`, EB shrinkage `tau/sigma` 0.00 (score) / 0.50 (gap),
  61 self-side fallbacks, 3 references with no qualifying foreign pair; 402 species,
  363 singletons, as in the harness.
- GBIF fetch succeeded on a fresh key (`served_from_cache_after_failure = FALSE`) after
  two earlier attempts that night died on GBIF's own 503 and a transfer timeout -- both
  now retried/fallback-handled in `download_gbif_occurrences()`.
- Training screen still INCOMPLETE: 761 pending (20 more evaluated before the breaker
  tripped again). Kept as 'untested'; harmless; it will keep chipping away per run.
- **Why run 2 beats arm C (810/885 agree):** the habitat cache holds the verdicts from
  the 2026-09-10 live test, not the ones run 1 drew uncached. Under the cached weights
  3 of *Moxostoma macrolepidotum*'s 17 nearby records read Lentic (run 1: 0), so it is
  `resident_observed` (theta 2.1e-3, 6.3 effective records; run 1: 1.1e-5, undetected)
  and it takes the redhorse calls with Lamar support (24 of 42) where *M. anisurum* had
  7 of 49. *Minytrema melanops* +21 supported for the same reason. This is the exact
  instability the cache exists to freeze; from here on the priors are reproducible.
- Largest remaining unsupported taxa: *Notropis hudsonius* 26 (was 20 in every run),
  *M. macrolepidotum* 18, *Umbra limi* 16, *Fundulus notatus* 10, *Esox lucius* 9.

## Site 2 outcome — PtConception 12S single-site, 2026-09-11 (finished 12:26, 261 min)

**Completed end to end on the new defaults. No ground truth here; checks are structural.**
13,440 ASVs; 9,113 species-rank / 3,080 genus / 1,228 family / 9 order; 151 consensus
taxa, 112 at species rank; final CSV 13,118 rows / 113 taxa. No earlier species list
survives to diff against (the checkpoints are overwritten in place), so this run is the
new baseline for the site.

- **Match-candidate screen (7a.10):** 708 driving accessions, all cache-served, 2
  actioned remove (OQ846263 *Rathbunella hypoplecta*, KM057967 *Jordania zonope*), 14 LLM
  overrides, none on a removal. **The hand override `VETO_AUDIT_SPARED = "OQ846263"` is
  still needed, not redundant**: the fresh production verdict is again `incongruent` /
  `remove` / no corroboration at max_hits 20 (the 2026-09-04 audit found it at 100).
- **Training screen (7a.11): did not run at all.** `ref_eval` 4,061 accessions, 0 from
  cache, 0 evaluated, 1,866 pending, breaker tripped on the first batch (NCBI was
  throttling all night); 2,195 read `keep` from local corroboration alone. 0 removed, 0
  pairwise rows dropped (the 2026-09-03 prediction of ~360 "unverified" drops was for the
  old mechanism; under the new one untested = kept). The 12S training-screen cache dir is
  new, so nothing was served. It will fill in over runs; harmless.
- **Coverage floor:** this site's externally built match object has no `query_coverage`
  column and no recorded BLAST floor, so `evaluate_likelihoods()`'s check is silent and
  0.8 is an assumption. The floor matters less here than at GreatLakes because the
  matrix was built `by_genus = TRUE` (capped foreign reps): 19% of references had a
  short-overlap best foreign pair (GreatLakes 81%). Measured on a 2,500-ASV sample,
  old-style vs this run: H1 near-ties 951 -> 679, median top/second 1.32 -> 1.58,
  agreement with the best BLAST hit 2,149 -> 2,174; global expected gap 0.154 -> 0.176.
  Smaller effect, same direction.
- **Shrinkage consequence worth knowing:** `tau2_score = 0` again (as at GreatLakes), so
  every species' H1 mean score is the global mean (1 distinct value across 691 species);
  species identity now lives in the gap mean (`tau/sigma` 0.50, weights up to 0.7) and
  the variance. Because of that, `calibrate_query_noise(offset_form = "linear")` -- which
  this workflow requests -- has no spread of trained means to fit a line through and
  falls back to the constant offset (`-0.073`, 6,604 confident obs, 44 genera), with its
  documented warning. That is the correct outcome, and it is the same conclusion the July
  train-vs-inference study reached from the query side; the `"linear"` request is now
  moot wherever EB collapses the score means.
- **Sentinel:** *Girella nigricans* at species rank in 175 ASVs, no genus fallback, no
  *G. simplicidens* leakage. Contamination: 10,218 `questionable_lab_contaminant` (the
  known March-run control situation, unchanged), 205 LLM `high`. Habitat cache 681 taxa.
- Top species by ASV count read as a coherent southern-California nearshore list
  (*Sardinops sagax* 1,433, *Scorpaenichthys marmoratus* 1,109, *Engraulis mordax*
  1,025, *Clinocottus recalvus* 843, ...) plus the usual human/cattle/pig/sea-lion/gray
  whale rows.

## Run 1 outcome — GreatLakes, 2026-09-10 (09:02–14:03, 296 min). Read before running site 2.

**Completed end to end; the rewiring worked; the Lamar numbers moved for reasons upstream
of the screen.** No console log was saved (run in RStudio), so every count was
reconstructed from checkpoints — save the console next time (`sink()` or Rscript `> log`).

- **Screen counts (reconstructed):** 7a.10 match-candidate screen: 1,073 driving
  accessions, all cache-served, 7 flagged/borderline, KJ135626 removed, NC_028197 spared
  by LLM review, 31 overrides (30 of them on accessions that were "keep" anyway). 7a.11
  training screen: 8 of 2,750 removed, 10,464 of 2,829,714 pairwise rows dropped.
  Likelihood ratio new/old on the 800 unchanged observations: median 1.00, 0.5% moved
  >26%. **The screen did not move the results.**
- **The training screen tripped NCBI's circuit breaker at 71.6%**: 781 of 2,750 never
  evaluated (`attr(ref_eval, "run_summary")$circuit_breaker_tripped`), kept as
  'untested'. The 4 rewired workflows now print an INCOMPLETE banner after each screen.
  Not worth a run on its own (expected yield ~3 more removals, likelihood effect ~0); it
  completes itself, cache-served, on the next run.
- **Audits:** `verify_local_corroborations()`: 291 thin rows, all clean (goal2 cache: 3
  Fundulus rows unchecked, corroborator column predates the cache). `verify_removal_
  candidates()`: match screen reproduced the KJ135626/MZ605481 one-corroborator rescue,
  corroborator BLAST CPU-budget rejected; training-screen audit timed out on all 8 and —
  bug, fixed same day — reported all 8 `spared = TRUE` (now NA).
- **Lamar (REVIEW_formal_lamar_check.R, saved as `*_postscreen.rds` beside the `_wcal`
  baseline):** co-detections 602 -> 593, ours-only 104 -> 144, precision 0.8527 ->
  0.8046; intersection 29/61 and overconfidence 1/1081 unchanged. 56/885 consensus calls
  changed: *Moxostoma* genus -> *M. anisurum* species (28, Lamar supports 7/49),
  Leuciscidae -> *Pimephales notatus* (7), *Ctenopharyngodon idella* -> Xenocyprididae
  (5, **grass carp lost**), *Paranotropis volucellus* -> *Rhinichthys cataractae* (4),
  *Notropis stramineus* -> *Notropis* (3), …
- **Cause 1 (fixed):** the habitat LLM step was uncached; *M. macrolepidotum*'s 16
  nearby records all read Lotic this run, it fell to `resident_undetected`, *M. anisurum*
  won on a 20x prior edge and was amplified 478x by `update_prior_from_consensus()`.
  55 of 462 taxa are amplified >10x by that update (max 736x). NEW
  `TaxaHabitat::build_habitat_lookup(cache_dir=)`, wired into every workflow.
- **Cause 2 (open):** the H1 gap feature is trained on short-overlap foreign pairs, so
  the likelihood is a near-tie on 728/885 ASVs and the prior decides. Grass carp lost to
  bighead carp at equal priors on likelihood 0.77 vs 0.95 (100% vs 96.4% identity).
  Decision doc: `REENTRY_PROMPT_h1_foreign_coverage_floor.md`.
- **Other indicators fine:** `irreducible_consensus` 290/595; *Perca flavescens* 78 obs
  at species; `add_slash_taxon()` genus-only warning 30 names on the fast fixture, 0 at
  full scale; only archived-function reference is in the documented dead GLMM branch;
  export filter symmetric, 882 CSV rows / 48 taxa.
- **For sites 2–4:** the habitat cache starts empty at each site, so run 1 at each site
  freezes that site's verdicts. Do not compare Lamar-style numbers across runs made
  before and after the cache landed. Inspect the cache for the site's known-sensitive
  taxa (*Girella nigricans* at PtCon 12S) before trusting a surprise.

## What was already verified before this run (2026-09-10, prior session), so don't re-derive it

- All 9 packages were freshly built 2026-09-10 and spot-checked to reflect every recent
  archival/retirement (`flag_reference_errors` absent from TaxaLikely,
  `suggest_unreferenced_species` present in TaxaLikely, `corroborate_references_locally`
  present in TaxaMatch, `create_sites_from_grid` absent from TaxaExpect). If the workflow
  session that actually runs these full workflows is a DIFFERENT R session than the one
  that did this check, re-verify `packageDescription("TaxaLikely")$Built` (and the other 8)
  shows a build timestamp from the current work, not an older one -- a stale in-memory
  package load in a long-running RStudio session is the one real "cache" risk this
  investigation found (see below), and it's invisible unless checked directly.
- All four fast smoke tests (`diagnostics/fast_workflows/run_*.R`) passed clean with only
  the already-documented expected warnings; the PtCon 18S result reproduced byte-identical
  to the last recorded run (`irreducible_consensus` 82 FALSE / 112 TRUE). This confirms the
  ecosystem-level plumbing (posterior/consensus/slash-taxon chain) still works after the
  session's changes -- it does **not** exercise the reference-screen rewiring itself (the
  fast fixtures are frozen snapshots of already-screened match objects, built before the
  rewiring). The fast tests are not a substitute for what this doc is about.
- **Investigated directly, not assumed**: none of the 4 affected workflow scripts gate the
  reference-screening/training section (`evaluate_reference_accessions()` ->
  `train_likelihood_model()`) behind a `file.exists()` check or an in-memory `exists()`
  check. Confirmed via direct inspection of all 4 files: the nearest `if (file.exists(...))`
  gate before `train_likelihood_model()` in every case belongs to the upstream GBIF/
  occurrence-fetch section (`raw_gbif_path`/`geo_outlier_path`/`bbox_cache`), hundreds of
  lines earlier, not the reference-screen/training block. No `lik_model <- readRDS(...)`
  path exists anywhere in any of the 4 scripts. **This means the new architecture will run
  fresh and unconditionally the moment any of these 4 scripts is executed through that
  point -- no on-disk checkpoint needs to be deleted for that reason**, and none was
  deleted. Existing checkpoints in `~/My Drive/Rscripts/eDNA/PtConception/`,
  `~/My Drive/Stats and Data/GreatLakes data/` (all predate 2026-09-08, e.g.
  `PtCon18SSchulte_lik_model.rds` from 2026-09-06, `PtConMifishSchulte_lik_model.rds` from
  2026-08-29) will simply be overwritten by the fresh run, in place, as always.
- The persistent per-accession `evaluate_reference_accessions()` NCBI-verdict caches
  (`ptcon_ref_eval_cache`, `ptcon_ref_eval_review_cache`,
  `GreatLakes2023BurnsHarbor_goal2_screen_ref_eval_cache`,
  `GreatLakes2023BurnsHarbor_training_screen_pilot_ref_eval_cache`, and the new
  marker-specific dirs the 18S script creates on first run) were **deliberately left
  alone**, not cleared. They are self-managing (versioned via `params_key`, asymmetric TTL
  -- `"congruent"` cached forever, `"incongruent"` 30 days, `"insufficient_*"`/
  `"not_evaluated_*"` 180 days) and clearing them would only cost real NCBI budget with no
  correctness benefit, since the underlying `evaluate_reference_accessions()` function
  itself was not changed by the retirement -- only its caller pattern was. Confirmed no
  production workflow passes `min_coverage=` to `evaluate_likelihoods()` either, so the
  2026-09-09 coverage-filter crash fix has zero current production relevance (nothing to
  check there this round).
- No production workflow passes `min_coverage=` to `evaluate_likelihoods()`; the
  2026-09-09 `evaluate_likelihoods()` coverage-filter crash fix is therefore not exercised
  by any of these runs. Don't spend time looking for its effect.

## Suggested run order

1. **GreatLakes first.** It's affected by the rewiring, has historically been the fastest
   full production run to complete among the affected sites, and — uniquely among these
   four — has a real, independent ground-truth (the Lamar species checklist) plus dedicated
   comparison tooling already built (`InspectConsensusWorkflowRun.R`, the various
   `REVIEW_*.R` scripts in that directory) — meaning it's the only one of the four where
   you can check *correctness*, not just *did it crash*. The last documented pre-rewiring
   Lamar baseline (2026-09-07, `TaxaLikely/CLAUDE.md`'s B2-closure note): precision 0.8527,
   species co-detections 602, unique-species intersection 29/61, overconfidence 1/1081.
   Re-run the same Lamar comparison after this run and see whether those numbers moved
   outside noise.
2. **PtConception 12S single-site second.** This is the most heavily pre-analyzed dataset
   for the reference-screen question specifically — its own workflow file's 7a.11 comment
   is the one other workflows' comments point back to for the motivating evidence (a real
   2026-08 GreatLakes audit found the *old* `flag_reference_errors()` heuristic was only
   3/231 confirmed genuine mislabels vs. 213/231 false positives). It also already has a
   hand-added override (`VETO_AUDIT_SPARED` in that script's `override_accessions=`) from
   an earlier `verify_removal_candidates()` audit — worth checking whether the fresh run's
   own `reference_action` verdicts still agree with it, or whether the override is now
   redundant/wrong under the new call pattern. A rough prior estimate of impact already
   exists (`project_reference_screen_overview_assessment_2026_09_03` memory: ~6 of 13,442
   real match hits change, ~360 training refs drop as unverified) — treat this as a
   *predicted* number to compare the *actual* run against, not a verified one.
3. **PtConception 12S multi-site third** — same architecture as #2, lower priority (a
   variant, not a different question).
4. **PtConception 18S_2 single-site fourth.** Same rewiring, but this site has historically
   been the slowest and most NCBI-throttled of the four (real multi-hour runs, repeated
   `HTTP 500`/CPU-budget rejections documented across many past sessions) — worth doing
   last so any basic bugs surface on the cheaper runs first.
5. **Mugu (Fish/WilderFish) last, lower urgency.** Neither script ever used the retired
   pattern, so this run mainly regression-checks the *broader* archival work from this
   session's own retirement/archival sweep (see the next section), not the reference-screen
   rewiring specifically.

## What to actually check after each run

**Crash-level, first:**
- Did the script complete end to end? Read the full console output, not just the exit
  code — several of these functions warn loudly on real, expected edge cases (e.g.
  `evaluate_likelihoods()`'s "N observation_id(s) produced no usable likelihoods" is
  normal, not a bug) and it's easy to mistake a real error buried mid-log for one of those.
- `message()` lines from the reference-screen step itself report real counts directly —
  don't re-derive them by hand:
  - `"Local corroboration: %d of %d driving accessions corroborated..."` (Step 7a.10, the
    match-candidate screen)
  - `"Match-candidate screen: %d flagged/borderline, %d actioned 'remove', %d vetoed by
    local corroboration, %d skipped as locally corroborated, %d overridden by LLM
    review."`
  - `"Training reference screen: %d of %d accession(s) recommended for removal; %d
    pairwise row(s) dropped from training (of %d)."` (Step 7a.11, the new training-set
    filter that used to be `flag_reference_errors()`'s job)

**Before trusting any `reference_action == "remove"` list, run the audit tools built for
exactly this:**
- `TaxaMatch::verify_removal_candidates(evaluation, ..., screen_corroborators = TRUE)` on
  the `ref_eval`/`match_eval` objects each script saves (`.save(ref_eval, "ref_eval")`,
  `.save(match_eval, "match_eval")`) — this is the tool that caught the real KJ135626/
  MZ605481 false-rescue case (an accession spared by exactly one corroborator that was
  itself a documented mislabel). A `spared = TRUE` row is a prompt to look, not a
  conclusion.
- `TaxaMatch::verify_local_corroborations()` on any `hierarchy_flag == "locally_
  corroborated"` rows resting on `<= 2` independent conspecifics — the free, no-NCBI-call
  audit of the *other* thin-corroboration population.
- If either surfaces a real bad call, the fix belongs in the workflow's own
  `override_accessions=`/`resolve_review_overrides()` list, following the pattern
  `PtConceptionWorkflow_12S_single_site.R`'s own `VETO_AUDIT_SPARED` already established —
  not a package-level change, unless the SAME failure mode recurs across multiple real,
  independent accessions (in which case it may indicate a real gap in
  `evaluate_reference_accessions()`/`score_reference_labels()` itself, worth a fresh
  investigation, not a one-off override).

**Known regression indicators already established in this ecosystem — check these exist
and look sane, don't just check for their absence of error:**
- `irreducible_consensus` FALSE/TRUE split (the 2026-09-04 order-invariance regression
  indicator — a real bug once silently dropped irreducible multi-candidate units; see
  `TaxaID/CLAUDE.md`'s 2026-09-04 entry). Compare the split's rough shape against the fast
  smoke test's own numbers for the same site if one exists.
- Site-specific known-sensitive taxa: `Perca flavescens` (GreatLakes — walleye/perch
  resolution has a long, documented debugging history), `Fundulus lima`/`F. parvipinnis`
  (Mugu — this ecosystem's single most-debugged real edge case, Sessions 158-159; not
  expected to move since Mugu is unaffected by this rewiring, but worth a sanity check that
  it *still* resolves the same way after the broader package updates), `Girella nigricans`
  (PtConception 12S).
- `add_slash_taxon()`'s genus-only-name warning (documented, not-yet-investigated finding
  in `diagnostics/fast_workflows/README.md`) — check whether it fires at a similar rate at
  full scale as it did on the small fixtures, or whether it's dramatically different (which
  would suggest the reference-screen change is pushing more/fewer observations into
  genus-level fallback than before).

**Broader regression check (not specific to the reference-screen rewiring), since this is
the first full run since a large multi-session archival/retirement sweep:**
- Confirm nothing in the run's own console output references a since-archived function by
  name (would surface as an R error, not silently) — `flag_reference_errors`,
  `remove_flagged_references`, `build_site_reference`, `compute_likelihoods`,
  `model_likelihoods`, `calibrate_coverage_filter`, `coverage_threshold`,
  `create_sites_from_grid`, `compute_adaptive_sampling_groups`.
- Watch for the new `estimate_kernel_priors()` single-taxon-group warning (2026-09-09) if
  any of these sites use `sampling_group_col` — it's informational only (doesn't change
  output), but worth confirming it reads sensibly rather than firing on every group.
- The `suggest_unreferenced_species()` package-placement move (TaxaAssign -> TaxaLikely,
  2026-09-08) surfaces as a package-load masking message
  (`The following object is masked from 'package:TaxaLikely': suggest_unreferenced_
  species`) whenever both packages are loaded — cosmetic, already observed during this
  session's own fast-smoke-test runs, not a bug.

## What NOT to spend time on this round

- The `evaluate_likelihoods(min_coverage=)` crash fix — confirmed no production workflow
  uses it.
- Chasing whether any on-disk checkpoint is "stale" — confirmed the reference-screen
  section always recomputes fresh regardless of what's on disk.
- Manually clearing the NCBI-verdict caches — confirmed self-managing; clearing them wastes
  real NCBI budget for no benefit.

## If you find a real bug

Follow this project's own established convention: read the relevant package's `CLAUDE.md`
top session note and the specific function's roxygen before proposing a fix, verify against
real data (not just the failing case) before generalizing, and prefer the "flag, don't
silently exclude" pattern this ecosystem has independently re-learned three times already
(`apply_coverage_constraints()`, `TaxaFetch::filter_gbif_quality()`,
the 2026-08-08 mislabel-probability-weighting closure) if the fix involves a quality-based
exclusion decision. Record the finding in the relevant package's `CLAUDE.md` and, if it's a
real behavior/signature change, in `ecosystem_docs/NAME_CHANGE_HISTORY.md` too.

## PtConception 18S run outcome (2026-09-12, Fable 5.1)

First full 18S run on the rewired screen (`PtCon18SSchulte_*`, finished 13:55).
Two package bugs surfaced and were fixed mid-run (both committed):
`TaxaMatch::.trim_queries_to_amplicon()` errored on any marker with no
registered primer pair (18S), killing the match screen on chunk 1 (4a910ab);
`TaxaTools::scientific_to_common()` ran 58 silent sequential LLM calls on
1,151 names with no progress output and no cache (now `cache_dir`/`verbose`).

| Quantity | Value |
|---|---|
| Observations / consensus taxa | 10,968 / 1,151 |
| Consensus rank: species / genus / family / order / NA | 4,868 / 4,364 / 918 / 97 / 721 |
| Plausibility: expected / unexpected / unprecedented | 929 / 335 / 9,703 |
| Likelihood model | 3,380 species, sqrt_mismatch, floor 0.8, EB; tau/sigma score 0.27, gap 0.48 |
| Calibration | constant (by design at 18S) |
| Training screen | 21,899 accessions: 7,492 locally corroborated, 14,407 pending, breaker tripped at once, 0 removed |
| Match screen | 3,410: 402 evaluated (125 congruent, 30 incongruent, 92 insufficient, 12 oversized, 14 wrong-marker), 3,008 pending, 20 actioned remove |
| LLM review overrides | 49 (8 of the 20 removals kept); 12 accessions actually removed (274 rows) |
| Removal audit | all 20 `untested` (NCBI poll timed out at 100 hits on ~1.8 kb 18S queries) -- removals stand unaudited |
| Review flags | geographic unlikely 8,295 (8,221 of them on unprecedented rows: the skepticism gate); habitat unlikely 869; scope unlikely 929; contamination high 75 |
| Final list | 2,513 rows pass the four LLM filters, 1,640 rows / 191 taxa after the marine filter |
| Habitat cache | 2,027 taxa, 2,024 served from cache |

Reading: the 18S final list is governed by the geographic gate, not by the
likelihood model. 9,703 of 10,968 rows are `unprecedented` because only 108 of
the 701 species-rank consensus taxa have a named prior row (GBIF has almost no
protist/phytoplankton occurrence data), and the skepticism gate then rates
8,221 of those geographically unlikely. That is the designed behaviour
(validated 2026-09-06), but it means the 18S species list is a GBIF-coverage
list as much as an eDNA list. Per-group CSVs were not written: `sampling_group`
lives only on the occurrence side and never reaches the consensus table, so
Step 10's `any_of("sampling_group")` split is dead code at this site.
Cosmetic: 9 `Unknown or uninitialised column: usageKey/rank` warnings from
`get_keys_from_context()`'s rank-recovery fallback at Step 3.

Console log: every message after the first (primer) crash is missing while
prints kept arriving -- the handlers were gone but the sink was not (a mid-run
reinstall/restart is the likely cause; a top-level error, a nested error and an
rlang abort were all tested and do NOT drop `globalCallingHandlers()`). The
block in all 8 workflows now re-registers tagged handlers when absent and
appends to the day's existing log after a restart.

Next: run `inst/screen_training_references_standalone.R PtCon18S` overnight
(14,407 pending) and re-run the 18S match screen step later (3,008 pending);
PtCon 12S multi-site and MuguFish still to run.

## PtConception 12S multi-site: FAST version built and run (2026-09-12, Fable 5.1)

`PtConceptionWorkflow_12S_multi_site.R` had not run since 2026-07-13 and was
barely multi-site (one kernel fit at STUDY_LAT/LON; the only multi-site element
was the spatially gated consensus update). NEW
`PtConceptionWorkflow_12S_multi_site_FAST.R` (same directory) reuses the
single-site run's checkpoints for everything identical (contaminant flags,
occurrences, priors at the STUDY site, match object, references, model,
likelihoods, coverage, iNat) and computes only the multi-site part: a site table
from the Dangermond metadata (BioD 34.4425/-120.4535, Cojo 34.4529/-120.4183,
Jalama 34.5096/-120.5017), one kernel fit per Location with the single-site
run's calibrated bandwidths (25 km, 250 m depth), evidence rows replicated per
site, `join_priors(site = <obs x site>)` -> `combine_multisite_priors()` ->
posterior -> spatially gated consensus update, review (cached), common names
(cached), final CSV, and a side-by-side comparison with the single-site
consensus. August-only sequences get their own singleton spatial group (the
old file's open question). FAST_SUBSET: 1,218 of 13,440 sequences (579
multi-Location, 450 single-Location, 100 no-site, 96 sentinel-topped); 1.6 min
end to end once the review cache is warm.

FOUND AND FIXED (TaxaAssign 2d3cdf9): `combine_multisite_priors()` returned
NaN/Inf for 349 of 4,469 candidate rows -- every candidate whose per-site
priors were all J-shaped (dark-diversity floor alpha ~2e-6, evidence-blend
~6e-5): the logit combination underflowed to a mean of exactly 0. The
multi-site path had never met real priors before. Logit rule kept wherever
finite; probability-scale precision weighting when every site is J-shaped.

Results: per-site theta ratio (max/min) across 514 modelled species median
1.27, 90th pct 2.28, max 2.34 (sites 3.5-9 km apart, lambda 25 km); 2,099
candidate rows combined across 2-3 sites; consensus 770 species / 291 genus /
155 family; multi-site vs single-site consensus taxon agreement 99.2% at 1
Location, 99.4% at 2, 99.1% at 3, 96.6% for no-site sequences; the changes
are cottid genus/species flips (Clinocottus recalvus <-> Clinocottus,
Orthonopias triacis -> Cottidae) and one Hylobatidae. Final list 1,202
sequences / 72 taxa. Sentinels: Girella nigricans theta 8.8e-3 at every
site, Fundulus parvipinnis 4.2e-8 to 5.5e-8.

## Implausible-taxon audit and two fixes (2026-09-12, Fable 5.1)

Four implausible consensus taxa were traced (Prosopium williamsoni and
Pseudotolithus senegallus at Mugu; Sufflamen fraenatum and Symphalangus
syndactylus at PtCon 12S). All four were flagged (unprecedented, weak or
indistinguishable discrimination, LLM geographic "unlikely") and excluded
from every final list. Two mechanisms produced misleading species labels on
the way and were fixed:

1. **Downranking to a clamp-only species** (Mugu): posterior_consensus()'s
   species_reference narrowed a genus LCA (Pseudotolithus, three plausible
   congeners at 0.50/0.27/0.11) to P. senegallus (posterior 0.009, never
   plausible) and reported it at the genus's 0.89, because since curve
   pricing every zero-record BLAST candidate has a distance-clamp row in the
   priors table. FIX (all 7 workflows, `.bak_pre_downrank_yearrange`):
   clamp-only rows are excluded from the species reference. 1 of 145
   downranked rows across four sites was affected.
2. **Regional-proximity evidence from all-time GBIF records** (PtCon): a 1929
   SBMNH preserved specimen of a captive siamang ("Featherhill Ranch") 74 km
   away gave the species a weight of 0.031 (480x the floor) and beat the
   family-level hypothesis whose likelihood was 33x higher. FIX: the
   generator's `year_range` default is now the 2000-to-now window (was NULL,
   all time; TaxaExpect d0232cd) and every workflow passes its own YEAR_RANGE.

Sensitivity (`ecosystem_docs/regional_evidence_sensitivity_2026_09_12.csv`;
each site's regional-evidence taxa re-fetched with the study year window and
classified under the site's habitat scheme):

| Site | regional rows | lost by year filter | kept by year but Habitat != site | consensus winners among regional taxa (lost by year / habitat-fail) |
|---|---|---|---|---|
| PtCon 12S | 53 | 36 | 13 | 25 rows: Bubalus bubalis 9, Cervus elaphus 9, siamang 2, bison, channel catfish, red bat, cutthroat, steelhead (13 / 12) |
| Mugu | 22 | 9 | 11 | 4 rows: Pimephales promelas 2, coho, mountain whitefish (0 / 4) |
| GreatLakes | 132 | 42 | 81 | 0 -- no GL consensus winner rests on a regional-evidence row, so the year filter cannot move the Lamar validation |

Habitat gate NOT built (user decision pending): a hard gate (taxon's best
habitat must equal the site habitat) would also drop steelhead at PtCon
(Freshwater 0.75 / Marine 0.25) and 81 lotic darters at GL; the softer form
-- multiply the regional weight by the taxon's site-habitat weight from the
cached habitat lookup -- keeps steelhead at a quarter weight and zeroes the
mammals, whitefish and fathead minnow. GL unaffected either way (0 winners).

## Habitat conditioning of presence evidence -- BUILT and VALIDATED (2026-09-12, Fable 5.1)

Design agreed with the user (defensible, allows bleed): evidence rows now obey
the habitat stratification the resident priors already obey.
`TaxaExpect::condition_evidence_on_habitat()` (9c9ea9a):
`w_site = max(w * H_site, W_CLAMP)`, H_site = the taxon's weight for
SITE_HABITAT from the same cached LLM habitat lookup that supplies the
residents' point votes; W_CLAMP = the zero-evidence clamp
(`w_scale * exp(-d_cap/d_half)` = 6.36e-5). Product = P(present in the site
habitat | evidence) under distance/habitat independence (the geo x depth
product-kernel idiom); linear so bleed survives in proportion; floored so no
row sinks below a zero-evidence taxon. Applied to regional, watch-list and
iNat evidence in the kernel branches of GreatLakes, PtCon 12S single + multi
and MuguFish (`.habitat_condition()` wrapper; backups
`.bak_pre_habitat_conditioning`). The 18S workflow and the templates have no
evidence block.

Validated on the REAL workflow lines (harnesses execute the patched
workflows' own 7a.7 -> 7a.9b evidence block, kernel fit re-estimated at the
run's bandwidths, then 7b.5 -> 8h at GL / 8a -> 8i at PtCon, against the
2026-09-11 checkpoints; arm P = production priors reproduces production):

| Site | Arm P (control) | Arm H (year window + habitat) |
|---|---|---|
| GreatLakes Lamar species-level | both 840, ours_only 141, precision 0.856, 42/61 species | both 840, ours_only 123, **precision 0.872**, 42/61 species; grass carp 5, yellow perch 78, walleye 42 unchanged |
| GreatLakes consensus vs production | 885/885 | 875/885: Moxostoma macrolepidotum -> Moxostoma x8 (golden redhorse gained an iNat row at Lentic 0.2), Etheostoma -> E. nigrum x1 |
| GreatLakes evidence rows | regional 132 | regional 90 (18 floored), iNat 7, watch 13; sum(w) 1.95 vs Chao 22.5 |
| PtCon 12S consensus vs production | 13426/13440 (MC noise) | 13404/13440 (99.73%): Bubalus bubalis -> Bovidae x9, siamang -> Hylobatidae x2, red bat -> Lasiurus, O. nerka -> Oncorhynchus x7, O. clarkii -> O. kisutch, Sardinops -> S. sagax; Girella nigricans 175 unchanged |
| PtCon 12S evidence rows | regional 53 | regional 17 (11 floored), iNat 3, watch 1, clamp 235; sum(w) 0.78 vs Chao 97.8 |

Cervus elaphus (x9), Bison bison and Ictalurus punctatus still win their
sequences at PtCon: each is the ONLY candidate, so no prior can move them --
they stay flagged unprecedented, like the triggerfish. Harness scripts:
`GreatLakes data/REVIEW_habitat_conditioning_arms.R` (arms P/H, scored by
`REVIEW_lamar_score_arm.R P|H`) and
`PtConception/REVIEW_habitat_conditioning_ptcon.R`; outputs in
`_coverage_floor_validation_2026_09_10/` (GL, arm letters P/H) and
`_habitat_conditioning_validation_2026_09_12/` (PtCon).
