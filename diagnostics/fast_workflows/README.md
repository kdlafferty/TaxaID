# Fast test workflows

**Why this exists:** full real-workflow testing (13k+ observations, live NCBI/GBIF/LLM
calls, hours per run) has been the single biggest cost to development velocity on this
project. This directory holds tooling to extract a small, curated, *real* fixture from a
full production checkpoint, so a code change can be validated in seconds/minutes instead
of hours -- without inventing synthetic data that might miss the exact edge cases that
matter.

## What's here

| File | Purpose |
|---|---|
| `build_fast_fixture.R` | General-purpose subsetter. Given any real match/reference-quality-shaped OR posterior-shaped checkpoint (one row per `observation_id` x candidate), pulls out (1) every observation touching a "flagged" value in a caller-specified set of columns (defaults target `reference_action`/`hierarchy_flag`/`validity_flag`, gracefully skipped when absent -- e.g. GreatLakes' checkpoint has neither), (2) observations with an unusually wide candidate set (stress-tests irreducibility/consensus logic), (3) a reproducible stratified random sample of ordinary observations for baseline coverage, and (4) via `always_include_taxa` (added 2026-09-05), any named taxa GUARANTEED present regardless of the `max_observations` budget -- so known problem taxa from past debugging sessions are never left to chance. |
| `ptcon12s_fast_match_obj.rds` | Real fixture from the **stable, completed** PtConception 12S run (`PtConMifishSchulte_match_obj_restored.rds`, last touched 2026-09-03 -- NOT the live 18S run). 374 observations / 1259 rows (~35KB): 150 "interesting" (caution/incongruent/insufficient-evidence/wide-candidate-set) + 50 stratified-random baseline + 174 guaranteed `Girella nigricans` observations. |
| `ptcon12s_fast_lik_model_calibrated.rds` | Companion calibrated likelihood model (182KB), copied read-only from the same stable run. |
| `run_fast_smoketest.R` | Chains `evaluate_likelihoods() -> compute_posterior() -> posterior_consensus() -> add_slash_taxon()` against the PtConception fixture. **Runs in ~3 seconds.** Flat placeholder prior (loudly labeled) -- no real priors checkpoint exists for this dataset. |
| `greatlakes_fast_match_obj.rds` | Real fixture from the **stable** GreatLakes 12S run (`GreatLakes2023BurnsHarbor_match_obj_restored.rds`, at `~/My Drive/Stats and Data/GreatLakes data/`, last touched Sep 4). 257 observations / 4592 rows (~99KB): 150 wide-candidate-set "interesting" + 30 baseline + 78 guaranteed `Perca flavescens` (Yellow Perch) observations. This checkpoint carries no `reference_action`/`hierarchy_flag` columns at all (a real schema difference from PtConception's). |
| `greatlakes_fast_lik_model_calibrated.rds` | Companion calibrated likelihood model (111KB), copied read-only from the same stable run. |
| `run_greatlakes_fast_smoketest.R` | Same pipeline as `run_fast_smoketest.R`, against the GreatLakes fixture. **Runs in ~6 seconds.** With the flat placeholder prior, real Yellow Perch observations correctly do NOT resolve to a single species (they share posterior mass with real congeners Sander/Zingel/Niphon/Perca fluviatilis/schrenkii with nothing ecological to discriminate them) -- expected placeholder-prior limitation, not a bug; see the script's own inline note. |
| `mugu12s_fast_posterior_df.rds` | Real fixture from `MuguWilderFish_blast_r1_12s.rds`'s `$posteriors` sub-object (at `~/My Drive/Rscripts/eDNA/SepulvedaMugu/`, stable). Already a real, fully-computed `compute_posterior()` output carrying genuine kernel-priors-derived `prior_mean`/`prior_alpha`/`prior_beta`, not a placeholder. 75 observations / 546 rows (~14KB): 7 wide-candidate-set "interesting" + 50 baseline + 19 guaranteed `Fundulus lima`/`Fundulus parvipinnis` observations (this ecosystem's single most-debugged real edge case -- Sessions 158-159). |
| `run_mugu_fast_smoketest.R` | Starts one stage later than the other two (`posterior_consensus() -> add_slash_taxon()` only, since real posteriors already exist) -- and with GENUINELY REAL priors, not a placeholder. **Runs in <1 second.** Real result: every Fundulus lima/parvipinnis observation correctly resolves to `Fundulus parvipinnis` at ~0.999 posterior, matching this ecosystem's documented real production outcome. |
| `ptcon18s_fast_match_obj.rds` | Real fixture from the LIVE 18S production run's `PtCon18SSchulte_match_obj.rds`, built 2026-09-05 while that run was still in progress -- read only after confirming the file was 83+ minutes stable (well past the 30-minute threshold), and only from Step 1's already-completed match object, never from a checkpoint the run was actively writing at build time. 200 observations / 841 rows (~40KB): 150 "interesting" (contamination-flagged/wide-candidate-set) + 50 baseline. No `always_include_taxa` -- 18S has no established problem-taxon precedent from past debugging yet (unlike the other three sites); add one here once a real 18S-specific debugging case exists. This checkpoint predates reference-quality screening and `restore_suppressed_candidates()` (no `hierarchy_flag`/`reference_action` columns yet) -- it's an earlier pipeline stage than the other three sites' fixtures. |
| `ptcon18s_fast_taxaexpect_priors.rds` | Real (not placeholder) kernel-priors output, copied from the same live run's `taxaexpect_priors.rds` (Step 5, already complete). Single-site kernel fit -- exactly 1 unique `grid_id` (`"Site_34.40_-120.40"`). |
| `ptcon18s_fast_lik_model_calibrated.rds` | **Added 2026-09-07** once the live 18S run completed `train_likelihood_model()`/`calibrate_query_noise()` (in fact the whole pipeline, through `review_assignments()`) -- copied from `PtCon18SSchulte_lik_model_calibrated.rds` after confirming it (and the run's final outputs) were 30+ hours stable, not a live write. This unblocks the smoke test below. |
| `run_ptcon18s_fast_smoketest.R` | **Added 2026-09-07.** `evaluate_likelihoods() -> join_priors() (REAL priors, not a placeholder) -> compute_posterior() -> posterior_consensus() -> add_slash_taxon()`. Same `Stage 1-5` numbering as the other two full-pipeline smoke tests, with Stage 2 now a real `join_priors()` call instead of a flat placeholder, since a real `taxaexpect_priors` checkpoint exists for this site. `join_priors()` called without `expansion_taxonomy`/`singleton_taxonomy` (both optional) -- only affects unmodelled/habitat-agnostic candidates, not what this test regression-checks. **Runs in ~35s** (the one smoke test here that makes a small, real, live NCBI/GBIF backbone-verification call inside `join_priors()` -- ~10 names, not the full dataset -- still comfortably inside the "seconds/minutes not hours" bar, but the one exception to the other two tests' zero-network-call design). Live-run result (2026-09-07): 194 observations, no errors, `irreducible_consensus` 82 FALSE / 112 TRUE. |

## Safety note

Every `.rds` fixture here was built by *reading* (never writing to) an external directory
(`~/My Drive/Rscripts/eDNA/PtConception/`, `~/My Drive/Rscripts/eDNA/SepulvedaMugu/`,
`~/My Drive/Stats and Data/GreatLakes data/`), and only after confirming that specific
source file's mtime was NOT recent (no live run actively writing it). The PtConception 12S
source (`PtConMifishSchulte_match_obj_restored.rds`) is a **different, older, stable** run
than the `PtCon18SSchulte_*` checkpoints the live 18S workflow was writing at the time this
directory was first built. **The 18S fixture (`ptcon18s_fast_match_obj.rds`) is the one
exception, built deliberately from `PtCon18SSchulte_*` files while that run was still
live** -- but only after confirming those specific files (`match_obj.rds`,
`taxaexpect_priors.rds`) were 83+ minutes stable (no modification), i.e. output from a
pipeline stage that had already finished, never a file the run was actively writing at
that moment. This was an explicit user call (2026-09-05): pegging a fixture to a live
run's current stable stage is fine, understanding the fixture may need rebuilding once the
run progresses further -- the same maintenance cost as any upstream checkpoint changing
enough to make a cached fixture unrepresentative. Always check a source file's mtime
before reusing this tooling against a directory that might have a live run in progress
(this project's own established threshold is 30+ minutes stable), and never point
`build_fast_fixture.R`'s `output_path` at a directory a real workflow is currently reading
from/writing to.

## PtConception 18S: unblocked 2026-09-07

Previously staged-but-blocked (no trained likelihood model existed for this site yet).
**A smoke test is only meaningful if it exercises the SAME pipeline production actually
uses to make its calls** -- an earlier version of this file used `score_consensus()` as a
stand-in so *something* would run before the real model existed; that was corrected the
same day (2026-09-05) at the user's direct instruction and removed entirely, since
`score_consensus()` is a benchmarking/mimicry tool for comparison against the Bayesian
pathway, not what the real 18S workflow uses (see `TaxaAssign::score_consensus()`'s own
`@section Purpose`) -- a smoke test built on it would validate the wrong pipeline while
looking like it validates the real one.

The live 18S run has since completed through `train_likelihood_model()`/
`calibrate_query_noise()` (in fact the whole pipeline, through `review_assignments()`).
`ptcon18s_fast_lik_model_calibrated.rds` was copied in (confirmed 30+ hours stable, not a
live write) and `run_ptcon18s_fast_smoketest.R` was built following the exact
`evaluate_likelihoods() -> join_priors() -> compute_posterior() -> posterior_consensus() ->
add_slash_taxon()` shape used for PtConception 12S/GreatLakes, with Stage 2 now a real
`join_priors()` call (this site's real kernel-priors `taxaexpect_priors` checkpoint already
existed) instead of the flat placeholder the other two need. `site$grid_id` derived the
same way the real production workflow derives its kernel-mode `focal_grid` (the single
non-NA `grid_id` in `taxaexpect_priors` -- confirmed exactly 1, `"Site_34.40_-120.40"`),
not guessed. Ran successfully end to end 2026-09-07: 194 observations, no errors,
`irreducible_consensus` 82 FALSE / 112 TRUE, ~35s (see the table above for the one
network-call caveat this smoke test carries that the other two don't).

## Extending this to other sites/markers

The same pattern (`build_fast_fixture.R` against a stable, non-live real checkpoint, then
a short smoke-test script chaining the functions you actually want to regression-test) is
built out for PtConception 12S, GreatLakes, and Mugu 12S (PtConception 18S is staged but
blocked -- see above). Mugu's 16S/COI markers (`MuguWilderFish_blast_r1_16s.rds`/
`_r1_coi.rds`, same `$posteriors`/`$consensus` shape as the 12S source used here) are
unbuilt but should follow the exact same recipe as `mugu12s_fast_posterior_df.rds` above.
Each fixture only needs building once; re-run `build_fast_fixture.R` again only if the
upstream real checkpoint changes enough (a schema change, a large new batch of data) that
the cached fixture stops being representative -- this is a real, ongoing maintenance cost
for the 18S fixture specifically, since it was deliberately built from a live run's
checkpoint mid-flight (2026-09-05 call: pegging a fixture to a live run's current stable
stage is fine, and any changes that run surfaces get propagated the same way any upstream
checkpoint drift would be handled, rather than waiting for the run to fully finish before
building anything -- that call applies to the FIXTURE, not to substituting a different,
unrepresentative pipeline for the smoke test itself).

## Known real findings from the first run (2026-09-05), not yet investigated further

- `posterior_consensus()`'s automatic `rank_system` detection does not gracefully handle
  an input with zero taxonomy-rank columns (e.g. `evaluate_likelihoods()`'s own output,
  which only carries `taxon_name`/`taxon_name_rank` forward by design) -- errors deep
  inside `.find_lca()` with a cryptic "subscript out of bounds" rather than falling back
  to genus/species derivation from the binomial, which its own documentation says is
  always possible. Workaround used here: pass `rank_system` explicitly. Worth a look in
  the critical fix-quality review pass.
- `add_slash_taxon()` warns that ~30 genus-only names (e.g. `Pan`, `Gibbonsia`,
  `Oligocottus`, `Clinocottus`, `Hypsoblennius`) are reaching its slash-name formatter on
  this real dataset, which its own docs say can corrupt formatting. Not a placeholder-prior
  artifact -- reproduces regardless of the prior used. Worth checking whether genus-level
  fallback hypotheses are reaching this function in cases they shouldn't.

## Real finding from the first PtConception 18S run (2026-09-07) -- FIXED same day

`TaxaAssign::join_priors()`'s internal `TaxaMatch::filter_redundant_hypotheses(result,
rank_system = rank_system)` call warned `"rank_system name(s) not found as a column in
match_df (check for typos): species"` whenever `join_priors()` was called with
`rank_system = c("order", "family", "genus", "species")` against `evaluate_likelihoods()`'s
own output (which, by documented design, only carries `taxon_name`/`taxon_name_rank`
forward, never a literal `species` column) -- NOT specific to this smoke test; the real
`PtConceptionWorkflow_18S_2_single_site.R` production workflow (and every other real
single-marker workflow) passes the identical `rank_system` to its own `join_priors()` call
against the same kind of input, so this fired on every real production run too, previously
unnoticed.

**Investigated and fixed at the root cause in `TaxaMatch::filter_redundant_hypotheses()`
itself.** Traced the exact redundancy-comparison loop: `rank_system`'s own FINEST entry
(here, `"species"`) is provably never consulted as a comparison column by the algorithm --
a row AT the finest rank is always skipped before its own column would matter (line
~372's `next`; nothing is finer, so it can never be superseded), and no coarser row's own
comparison ever needs it either (its position in `rank_system` is always last, so
`cols_to_check <- rank_cols_present[seq_len(ri_in_present)]` for any coarser row never
reaches it). A missing column for the finest rank is therefore 100% inert -- the warning
was a genuine false positive, not a symptom of anything the algorithm actually needed.
Fixed by excluding `rank_system`'s own last element from the "must have a matching
column" check (a genuinely load-bearing missing COARSER column still warns, confirmed by
a new regression test). 2 new tests in `test-filter_redundant_hypotheses.R`;
`devtools::test()` 1370/0 (TaxaMatch), `devtools::check()` 0/0/0, reinstalled. Re-ran
this smoke test after reinstalling: the warning is gone, output is otherwise byte-identical
(813 rows, `irreducible_consensus` 82/112 unchanged) -- confirms this was a pure
warning-suppression fix with zero behavioral change, as the trace predicted. See
`TaxaMatch/CLAUDE.md`'s own 2026-09-07 top session note for the full record.
