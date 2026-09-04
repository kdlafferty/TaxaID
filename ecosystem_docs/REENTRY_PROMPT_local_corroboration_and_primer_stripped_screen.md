# REENTRY: local corroboration + primer-stripped screen query

Written 2026-09-03 (Fable 5.1 session, with the user). Implementation intended
for a delegated agent, offline; live NCBI validation reserved for the user.
Branch suggestion: `local-corroboration`.

## Why this exists (one paragraph)

`TaxaMatch::evaluate_reference_accessions()` is the BLAST-based reference
screen. It is expensive (NCBI CPU budget) and, as found today, has a
systematic blind spot. The user's question was: if an ASV matches several
references of the same species that agree with each other, why BLAST any of
them? The answer, measured on real PtConception and GreatLakes data, is that
(a) free local corroboration from the workflow's own `seq_matrix` removes
roughly 40% (PtCon) / 15% (GreatLakes) of the BLAST population, (b) it also
VETOES a wrong "remove" verdict, and (c) chasing why the veto disagreed with
BLAST exposed a real defect in the screen's query construction. All three
are built here.

## Evidence (all real, all reproducible without NCBI unless marked LIVE)

- PtCon 12S: 995 match-candidate accessions screened. `reference_action`:
  950 keep / 35 caution / 5 inspect / 4 remove / 1 untested. Only 6 of 13,442
  observations have a "remove" accession as their top hit.
- Tiers of the 995 by local corroboration (overlap >= 0.8, identity >= 0.99,
  independent submission batch; `diagnostics/local_corroboration_tiers_ptcon.R`):
  286 never the best accession for any (observation, species); 554 singleton in
  reference_df; 23 conspecifics only from the same batch; 26 disagree;
  106 independently corroborated. GreatLakes BurnsHarbor (1,182 candidates):
  97 / 869 / 70 / 66 / 80.
- **KM057996 (Zaniolepis frenata), actioned "remove" ("no conspecific evidence
  anywhere in nt"), has OQ846041 in the user's own reference_df: a 169 bp
  Z. frenata deposit from 2023, 100% identity over 97% overlap.** BLAST never
  returned it. LIVE probe (`diagnostics/blast_coverage_blindspot_probe.R`,
  2026-09-03): Run A (217 bp primer-inclusive query, 100 hits, coverage filter
  off) -> OQ846041 absent; the only conspecific hit was the query itself.
  Run C (same query with the MiFish-U primers stripped, 169 bp) -> OQ846041 at
  rank 2, score 100, coverage 100, bitscore 306; the 100th hit at 239.
- Mechanism (arithmetic, then confirmed by Run C): the screen runs blastn
  (`megablast = FALSE`, +2 match / -3 mismatch). A 169 bp perfect conspecific
  scores 338 raw against a 217 bp primer-inclusive query; every full-length
  relative at >= 93.1% over 217 bp scores >= 359. The server's
  `HITLIST_SIZE = 100` list is therefore filled by mitogenome relatives and the
  short perfect conspecific never arrives. Behind that, `blast_sequences()`'s
  default `min_query_coverage = 80` would have dropped it anyway
  (169/217 = 77.9%). With the primer-stripped query both barriers vanish.
- Scale of the blind spot: 1,357 of 4,061 PtCon references (33%) and 679 of
  2,750 GreatLakes references (25%) are <= 175 bp -- amplicon-only deposits,
  invisible as corroborators under the current query. How many of PtCon's 63
  `insufficient_independent_evidence` rows are this artifact is unknown until
  the re-BLAST below runs.
- Run C also showed OQ846089 and LC091896 (Zaniolepis latipinnis) at 100% over
  the full amplicon: the two Zaniolepis are NOT species-resolvable with
  MiFish-U. That is confusion-risk territory (`TaxaLikely` already computes
  it), not a mislabel. The hierarchy-congruence vote handles it correctly
  (congeners agree at family), so no change to the verdict logic is needed.
- A cautionary result from the same analysis: KM057967 (Jordania zonope) looked
  corroborated by LC126244 at "100%" -- over a 5.6% overlap (~40 bp, a different
  12S region). **Any local corroboration must filter `seq_matrix` on its
  `coverage` (overlap) column.** Jordania is a true singleton; its removal stands.
- Threshold: the motivating true mislabel MN883227 (Fundulus luciae, actually a
  Pacific Fundulus) is corroborated locally by five independent conspecifics at
  0.9814. A 0.98 threshold would veto/skip it; 0.99 keeps it screened. 98%
  between conspecifics is what a sister-species swap looks like, so the
  default is 0.99 and the parameter is documented as "must sit inside the
  marker's intraspecific range".

## What already exists (do NOT rebuild; read first)

- `TaxaMatch/CLAUDE.md` top notes for 2026-09-01 and 2026-09-02, and
  `REENTRY_PROMPT_eval_ref_accessions_long_sequence_robustness.md` +
  `REENTRY_PROMPT_reference_quality_verdicts_and_downstream_use.md`.
- `.trim_queries_to_amplicon()` (`R/trim_query_to_amplicon.R`) already locates
  `fwd_start/fwd_end` and `rev_start/rev_end` per sequence and returns the
  primer-INCLUSIVE span. `.resolve_trimmed_span_max()` is the one length bound.
- `.same_submission_batch()` / `.build_submission_batch_lookup()`
  (`R/evaluate_reference_accessions.R`) -- the independence rule. Reuse.
- `score_reference_labels()` / `refine_reference_verdicts()`
  (`R/reference_label_verdict.R`) emit `label_confidence`,
  `label_identity_margin`, `reference_action`. The pair-table sidecar
  `reference_pair_cache.rds` holds per-partner votes.
- `remove_incongruent_references(gate = "action")`,
  `flag_incongruent_references()`, `review_flagged_accessions()` (LLM second
  look), `verify_flagged_references()` (training-side bridge).
- `params_key` is one global string per cached row
  (`top_n|min_congruent_rank|submission_window|...|.EVAL_REF_ACC_VERSION`);
  `.EVAL_REF_ACC_VERSION = "v4_hybrid_maternal_proxy"`. Per-flag TTLs:
  congruent Inf, incongruent 30 d, insufficient/oversized 180 d.

## Design (five items, in build order)

### 1. Primer-stripped screen query (the defect fix)

`.trim_queries_to_amplicon()` gains `strip_primers = TRUE`: when both primer
sites are found, return `subseq(fwd_end + 1, rev_start - 1)` instead of
`subseq(fwd_start, rev_end)`. Keep the primer-inclusive path available
(`strip_primers = FALSE`). The length bound `.resolve_trimmed_span_max()` is
for the inclusive span; add the matching stripped bound (inclusive minus the
two primer lengths from `TaxaTools::resolve_barcode_primers()`), one
definition, both callers. Sequences with no primer sites are unchanged (a
169 bp deposit used as a query is already primer-free).

`evaluate_reference_accessions()` gains `query_span = c("amplicon",
"primer_inclusive")`, default `"amplicon"`. This CHANGES what is submitted,
so per the file's own rule it is verdict-affecting: bump
`.EVAL_REF_ACC_VERSION` to `"v5_amplicon_query"` and add `query_span` to
`params_key`. Do not silently keep the old key.

Because a bump invalidates ~3,000 real cached rows (PtCon 995; GreatLakes
1060 + 280 + 690), ship a migration helper alongside:
`migrate_reference_cache(cache_dir, from_key, to_key)` rewrites `params_key`
on rows whose `hierarchy_flag == "congruent"` and stamps a new
`migrated_from` column; every other row (incongruent, insufficient,
oversized) is left under the old key so it re-BLASTs under the new query.
Rationale, to state in the roxygen: `congruent` asserts corroborating
evidence WAS found; stripping primers only adds short-deposit hits to the
list, so it cannot withdraw an observed match. The actionable verdicts all
live in the non-congruent rows (PtCon: 76; GreatLakes: ~123), which is the
cheap part. Back up the cache file before rewriting (the 2026-08-11/13
`.bak_pre_*` convention).

`blast_sequences()`'s `min_query_coverage = 80` needs no change once the
query is the amplicon (a 169 bp deposit then covers 100%).

### 2. `corroborate_references_locally()` -- free evidence from `seq_matrix`

New exported function in TaxaMatch (it consumes plain data frames; no new
cross-package dependency, same reasoning as `verify_flagged_references()`).

```r
corroborate_references_locally(seq_matrix, reference_meta,
                               min_overlap = 0.8, min_pident = 0.99,
                               submission_window = 5)
```

- `seq_matrix`: `TaxaLikely::build_sequence_matrix()` output
  (`id_x, id_y, p_match, coverage, species.x, species.y`).
- `reference_meta`: `composite_id`/`accession`, `species`, `create_date`
  (the `fetch_ncbi_reference_sequences()` reference_df is exactly this).
- Conspecific pairs only, `id_x != id_y`, **`coverage >= min_overlap`**.
- Independence via `.same_submission_batch()` with the SAME lookup builder the
  screen uses (dates + accession prefix/number), so "independent" means one
  thing in both places.
- One row per accession:
  `n_conspecific`, `n_independent_conspecific`, `best_independent_pident`,
  `best_independent_partner`, `local_tier` in
  `{"singleton", "same_batch_only", "disagree", "corroborated"}`.
  `corroborated` = best independent identity >= `min_pident`;
  `disagree` = has independent conspecifics but none reach it.
- Strip version suffixes on both sides (`sub("[.][0-9]+$", "", x)`), the
  ecosystem convention.

### 3. `match_driving_accessions()` -- skip references that never matter

```r
match_driving_accessions(match_df, score_col = "score_original",
                         obs_col = "observation_id", species_col = "species",
                         accession_col = "accession")
```

Returns the accessions that are the max-scoring accession of their species
for at least one observation (ties kept). Everything else never drives a
likelihood (the per-species best is what `evaluate_likelihoods()` reads), so
no verdict on it can change an assignment. PtCon: 709 of 995. Document that
this is a cost filter for the SCREEN, not a change to the match object.
Drop `RESTORED_*` provenance accessions (the Mugu workflow already does this
by hand at its call site; do it here once).

### 4. Skip in `evaluate_reference_accessions()`

New params `local_corroboration = NULL` (the item-2 table) and
`skip_locally_corroborated = TRUE`. For an accession whose `local_tier ==
"corroborated"`, do not BLAST; write a cache row with
`hierarchy_flag = "locally_corroborated"`, `n_independent_top_matches =
n_independent_conspecific`, `best_agreeing_pident = 100 *
best_independent_pident`, `congruent_evidence_exists_anywhere = TRUE`,
`finest_common_rank = "species"`, the diagnostic columns otherwise `NA`,
`evaluated_at`, `params_key`. TTL Inf (it asserts evidence WAS found).
Verbose message: "N skipped: independently corroborated in the local
reference set". `remove_incongruent_references()`,
`flag_incongruent_references()`, `verify_flagged_references()` must treat
the new value as NOT a flag (add it wherever `"congruent"` is enumerated;
grep, don't guess). New flag value is additive -- no further version bump.

### 5. Veto + provenance in `score_reference_labels()`

New param `local_corroboration = NULL`. New output columns, always present:

- `corroboration_source`: `"local"`, `"blast"`, `"both"`, `"none"`.
  `blast` = `congruent_evidence_exists_anywhere`; `local` = tier corroborated.
- `local_best_independent_pident` (NA when no table supplied).
- `reference_action` veto: a row that resolves to `"remove"` with
  `local_tier == "corroborated"` becomes `"inspect"`, and
  `action_reason` (new column) records `"vetoed_by_local_corroboration"`.
  `label_confidence` is left as the BLAST-only probability -- do not fold
  local evidence into it; the two are kept separable on purpose so a reviewer
  can see them disagree (that disagreement is exactly what found the defect).
- `refine_reference_verdicts()` forwards the same argument.
- `review_flagged_accessions()`: add one line to the LLM prompt when the
  columns are present ("local reference set: N independent conspecifics,
  best identity X% over >= 80% of the amplicon"). Verify how that function
  builds its prompt before editing; keep it additive.

## Regression fixtures (build from these three real cases, offline)

- Zaniolepis: KM057996 with OQ846041 at p_match 1.0, coverage 0.97, dates
  2014-08-04 vs 2023-04-24, prefixes KM/OQ -> `corroborated`; a BLAST row
  reading incongruent/remove must come out `inspect`,
  `corroboration_source = "local"`.
- Jordania: KM057967 with LC126244 at p_match 1.0, coverage 0.056 ->
  `singleton` (the pair is excluded by `min_overlap`); "remove" stands.
- Fundulus: MN883227 with five OR3801xx partners at 0.9814, coverage ~1,
  plus MN883226 same-day (same batch) at 1.0 -> `disagree` at the 0.99
  default (the same-batch 1.0 must NOT count); at `min_pident = 0.98` it
  would be `corroborated` -- assert both, so the threshold's meaning is
  pinned by a test.
- Primer stripping: the real KM057996 record (718 bp) trims to 217 inclusive
  and 169 stripped; a 169 bp input passes through unchanged.
- Migration: a mock cache with congruent + incongruent rows under the old
  key -> only congruent rows carry the new key and `migrated_from`.

## Acceptance (offline)

- `devtools::document()`, `test()` 0 failures (baseline 1027 TaxaMatch),
  `check()` 0/0/0. Do NOT `devtools::install()`; leave that to the user.
- `diagnostics/local_corroboration_tiers_ptcon.R` reimplemented through the
  new function reproduces the tier counts above to within the ties.
- All ecosystem conventions: ASCII-only source, native pipe, `.` prefix +
  `@noRd` for internals, `utils::globalVariables()` first line where NSE,
  no blank lines in `@param` blocks, sprintf single-string discipline.
- Update `TaxaMatch/CLAUDE.md` top note, ecosystem CLAUDE.md Recent Breaking
  Changes (the version bump IS breaking for caches: say so, and point at the
  migration helper), `NAME_CHANGE_HISTORY.md`.

## Workflow call-site pattern (user applies; workflows live outside the repo)

```r
local_corr <- TaxaMatch::corroborate_references_locally(seq_matrix, reference_df)
to_screen  <- TaxaMatch::match_driving_accessions(match_obj_restored)
match_eval <- TaxaMatch::evaluate_reference_accessions(
  to_screen, cache_dir = ..., barcode_term = "MiFishU",
  local_corroboration = local_corr)                      # query_span default "amplicon"
match_eval <- TaxaMatch::score_reference_labels(match_eval,
  local_corroboration = local_corr, overwrite = TRUE)
```

Note the ordering constraint: `seq_matrix` must exist before the screen. In
PtCon 12S the screen currently runs BEFORE `build_sequence_matrix()`; move
the screen after it (the match object is not consumed in between -- verify).

## Re-run instructions for the next live NCBI window (after install)

Follow the four-step checklist: restart R; install TaxaMatch from the branch
with `.libPaths()` set first and verify
`"query_span" %in% names(formals(TaxaMatch::evaluate_reference_accessions))`;
un-cache: run `migrate_reference_cache()` on each real cache dir (PtCon
`ptcon_ref_eval_cache`, the three GreatLakes `*_ref_eval_cache` dirs) -- it
backs up first; verify `.libPaths()` again before the run. Then re-run the
screen. Expect: the 76 PtCon non-congruent rows re-BLAST under the amplicon
query; KM057996 should read congruent with OQ846041 among its partners; the
`insufficient` count should fall if the blind spot was inflating it. Report
the before/after `table(hierarchy_flag)` and `table(reference_action)`.

## Out of scope, deliberately

- Any likelihood-side use of these columns (closed twice:
  [[project_mislabel_probability_weighting_closed]], Thread 3 removal
  2026-09-02).
- Raising `max_hits`/`HITLIST_SIZE`: not needed once the query is the
  amplicon (Run C: the conspecific ranks 2nd of 100).
- Re-deriving the 0.99 threshold from the trained H1 within-species
  distribution: a good later refinement; record it, do not build it now.

## Status

- 2026-09-03: IMPLEMENTED (delegated agent, offline, mocked BLAST) on branch
  `local-corroboration`; tests 1228/0, check 0/0/0. Verified independently:
  the PtCon tier diagnostic reproduces 286/554/23/26/106 through the package
  and the veto flips exactly KM057996. Subset workflow test
  (`diagnostics/subset_workflow_local_corroboration_test.R`) RUN LIVE, 6/6
  checks pass; KM057996 forced through the amplicon query reads congruent
  with OQ846041 + two Z. latipinnis at 100%.
- 2026-09-03: MERGED into `kernel-priors` (6d7d3d9) plus 9ce583b (the screen
  now forwards `local_corroboration` into its own scoring). Workflows rewired
  (PtCon 12S 7a.10, GreatLakes 7a.6 -- a stale hard-coded `match_eval <-
  readRDS()` reload removed there -- and Mugu); backups
  `*.bak_pre_local_corroboration`.
- 2026-09-03: INSTALLED + MIGRATED + LIVE-VERIFIED on PtCon only. Reinstalled
  TaxaMatch from the `kernel-priors` main checkout (both the user's live
  session and, separately, Claude's Bash-tool `Rscript` invocation -- the
  latter explicitly targeted `~/Library/R/4.0/library` per
  `feedback_rscript_install_library_mismatch`; `packageDescription()$Built`
  and `"query_span" %in% names(formals(evaluate_reference_accessions))`
  verified true after a real restart). Ran `migrate_reference_cache()` once
  on all four real cache dirs; all backed up
  (`reference_accession_cache.rds.bak_pre_v5_amplicon_query`):
  PtCon 919 congruent carried / 76 left to re-evaluate (incongruent 12,
  insufficient 63, oversized 1); GreatLakes goal2_screen 1048/12; Plate1
  249/31; pilot 610/80. GreatLakes and Mugu were migrated but NOT yet run
  live (see below).
  PtCon 12S 7a.10 run LIVE (`PtConMifishSchulte_match_review.rds`, 709-row
  driving-accession subset, `evaluated_at` up to 2026-09-03 21:29:36):
  `hierarchy_flag` congruent 651 / incongruent 5 / insufficient 34 /
  locally_corroborated 18 / oversized 1; run_summary 639 from cache, 52
  evaluated this call, 18 skipped locally corroborated. All three
  predictions confirmed, with the exact reconciliation for anyone comparing
  to the "~106 skipped" / "~76 re-BLASTed" figures above:
  - KM057996 no longer removed -- better than predicted: caught by the skip
    BEFORE any BLAST call (`hierarchy_flag = "locally_corroborated"`,
    `action_reason = "locally_corroborated_not_blasted"`), not merely
    vetoed from remove to inspect.
  - The "~76 re-BLASTed" figure was over the full 995-accession cache; the
    screen only ever sees the 709 driving accessions
    (`match_driving_accessions()` runs first), so only 70 of the 76
    leftover rows were in scope this run (52 BLASTed + 18 skipped). The
    other 6 belong to non-driving accessions and correctly never entered
    the call.
  - The "~106 skipped" figure was "how many accessions are locally
    corroborated," not "how many get skipped on a given run": split
    `corroboration_source`, 88 rows are `"both"` (already had a valid
    BLAST-congruent cache row carried forward by the migration, so they
    hit cache before ever reaching the skip branch) and 18 are `"local"`
    (freshly corroborated this call, actually skipped). 88 + 18 = 106,
    exactly the diagnostic count. **This split is the thing to check first
    on any future run that looks like it "skipped too few": count
    `corroboration_source %in% c("local","both")`, not just
    `hierarchy_flag == "locally_corroborated"`.**
  - 2 removals remain (down from 4): Jordania zonope KM057967 (pinned by
    the fixture as a true singleton -- the LC126244 "100%" match is a
    5.6%-overlap artifact) and Rathbunella hypoplecta OQ846263 (also
    `corroboration_source = "none"`, no independent evidence anywhere).
    Neither was a blind-spot victim.
  - 1 untested (HM561627, the oversized 16S bat contaminant), unaffected as
    expected.
  - MN883227 (Fundulus luciae) reproduced unchanged: `insufficient_
    independent_evidence` / keep, `local_n_independent_conspecific = 5` at
    `local_best_independent_pident = 98.14`, below the 0.99 threshold so it
    lands in "disagree" locally and is not vetoed -- see loose end (1) below.
  - `devtools::test()` re-run after install: 1228/1228 pass, 0 failures/
    warnings.
- **CORRECTED 2026-09-04: GreatLakes HAS now been live-run** (2026-09-04
  09:38). `GreatLakes2023BurnsHarbor_match_eval.rds` holds 1,073 driving
  accessions: 1,058 congruent, 3 incongruent, 4 insufficient, 8
  locally_corroborated; 1,064 keep / 7 caution / 2 remove. The two removals are
  `KJ135626` (*Pseudorasbora parva*) and `NC_028197` ("Serranidae sp.
  JL-2015"), both already on record, and BOTH came back at the `max_hits` cap
  (20 and 19 of 20) -- i.e. both are exposed to the veto-truncation problem
  found on PtConception the same day. `PREP_greatlakes_screen_recheck.R` (GL
  data dir) audits them for 2 BLAST calls. Mugu is still not run.
  Two things this correction supersedes: (a) a workflow re-run now costs ZERO
  NCBI calls (all 1,073 driving accessions are cache-fresh under the current
  key), so it buys only the post-hoc columns -- the new audit columns
  (`query_trim_path` etc.) are computed during EVALUATION and stay `NA` until
  rows genuinely re-evaluate; (b) the Plate1 cache's Phoxinus/Etheostoma
  zero-partner block is a TRAINING-reference population reached only by
  `VerifyAllFlaggedTrainingReferences.R`, never by the workflow, so the
  workflow cannot speak to it.
- **Original note, now stale: NOT YET LIVE-RUN: GreatLakes
  (`GreatLakes2023_ConsensusWorkflow.R` 7a.6) and Mugu.** Caches are migrated (see counts above) but nobody has
  executed the screen against the new `query_span = "amplicon"` code path
  on those workflows. What to check when that run happens, for debugging:
  - Confirm `table(match_eval$hierarchy_flag)` sums to the *driving*
    accession count for that workflow (not the raw cache row count) --
    PtCon's population dropped from 995 candidates to 709 drivers via
    `match_driving_accessions()`; GreatLakes/Mugu will have their own,
    different reduction. If the workflow script wasn't actually rewired to
    call `match_driving_accessions()` before the screen (verify against the
    `*.bak_pre_local_corroboration` diff at that call site), the row count
    will instead match the full migrated-cache population and every number
    below will look inflated.
  - Expect the same `corroboration_source` reconciliation pattern as PtCon:
    `"local"` (freshly skipped this call) will undercount total corroborated
    evidence; add `"both"` (already cache-hit congruent from the migration)
    to get the true corroborated count. Don't read a low
    `n_skipped_locally_corroborated` in `run_summary` as the fix
    underperforming without checking this split first.
  - GreatLakes' three cache dirs have different left-to-reevaluate profiles
    (goal2_screen 12, Plate1 31, pilot 80) -- run each workflow's relevant
    dir and match the printed cache path to the dir you expect, since three
    dirs exist and it is easy to point at the wrong one.
  - No fixture accession is pinned for GreatLakes the way KM057996/Jordania/
    Fundulus are for PtCon; the closest analog on record is the two real GL
    removals from the pre-migration screen audit, NC_068731 and KJ135626
    (both PtCon-era "true singletons" per
    `project_reference_screen_overview_assessment_2026_09_03`) -- worth
    checking by name that neither flips.
  - Mugu has no cache at all (`RUN_ACCESSION_SCREEN` gated off historically);
    its first live run will show 0 cache hits and is the first real test of
    `match_driving_accessions()` wiring there (rewired per the merge note
    above, restoring a `grep` that had done the same job by hand).
- Two loose ends for a later session (not today, not GreatLakes/Mugu-blocking):
  (1) MN883227 (Fundulus luciae, the "confirmed mislabel") reads insufficient/
  keep with ONE independent BLAST partner, NC_083019, a F. luciae mitogenome
  at 100%, and locally at 5 partners / 98.14% (below veto threshold) --
  re-examine that premise; (2) 743 of 995 PtCon match candidates are absent
  from reference_df, so local corroboration reaches only ~25% of candidates
  there; a reference fetch that also pulls the match candidates' conspecific
  short deposits would widen it (not designed).
