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
