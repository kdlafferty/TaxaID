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
| `ptcon18s_fast_match_obj.rds` | Real fixture from the LIVE 18S production run's `PtCon18SSchulte_match_obj.rds`, built 2026-09-05 while that run was still in progress -- read only after confirming the file was 83+ minutes stable (well past the 30-minute threshold), and only from Step 1's already-completed match object, never from a checkpoint the run was actively writing at build time. 200 observations / 841 rows (~40KB): 150 "interesting" (contamination-flagged/wide-candidate-set) + 50 baseline. No `always_include_taxa` -- 18S has no established problem-taxon precedent from past debugging yet (unlike the other three sites); add one here once a real 18S-specific debugging case exists. This checkpoint predates reference-quality screening and `restore_suppressed_candidates()` (no `hierarchy_flag`/`reference_action` columns yet) -- it's an earlier pipeline stage than the other three sites' fixtures. **Staged, not yet paired with a smoke test -- see "PtConception 18S: staged, blocked" below.** |
| `ptcon18s_fast_taxaexpect_priors.rds` | Real (not placeholder) kernel-priors output, copied from the same live run's `taxaexpect_priors.rds` (Step 5, already complete). |

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

## PtConception 18S: staged, blocked

A smoke test is only meaningful if it exercises the SAME pipeline production actually
uses to make its calls. For every other site here, that's the Bayesian pathway:
`evaluate_likelihoods() -> compute_posterior() -> posterior_consensus() -> add_slash_taxon()`,
which needs a real trained `lik_model` (`TaxaLikely::train_likelihood_model()` +
`calibrate_query_noise()`). At the time `ptcon18s_fast_match_obj.rds`/
`ptcon18s_fast_taxaexpect_priors.rds` were built (2026-09-05), the live 18S run had reached
priors (Step 5) but not yet `train_likelihood_model()` (Step 7 -- still fetching reference
sequences / training, both real NCBI-bound steps with no intermediate checkpoint) -- so no
`lik_model_calibrated.rds` exists for 18S yet.

**An earlier version of this file used `score_consensus()` as a stand-in** (a
no-likelihood-model pathway that needs only `match_obj`) so *something* would run today.
That was the wrong call, corrected the same day at the user's direct instruction:
`score_consensus()` is documented as a benchmarking/mimicry tool that deliberately
reproduces a conventional fixed-threshold pipeline for COMPARISON against the Bayesian
pathway (see `TaxaAssign::score_consensus()`'s own `@section Purpose`) -- it is not what
the real 18S workflow uses to make its actual calls, so a smoke test built on it would
validate the wrong pipeline while looking like it validates the real one. Removed
entirely rather than kept as a partial substitute.

**The fixture and priors above are staged and ready** -- once the live run produces
`PtCon18SSchulte_lik_model_calibrated.rds` (or an equivalent, e.g. from a completed re-run),
copy it here the same way the other three sites' companion `lik_model_calibrated.rds`
files were copied (checking its mtime for live-write safety first), and build
`run_ptcon18s_fast_smoketest.R` following the exact same
`evaluate_likelihoods() -> join_priors(taxaexpect_priors = <the real ptcon18s priors>) ->
compute_posterior() -> posterior_consensus() -> add_slash_taxon()` shape as
`run_fast_smoketest.R`/`run_greatlakes_fast_smoketest.R`. Note `join_priors()` will need a
`grid_id`/`main_habitat` or `lat`/`lon` -- read these off the live workflow script's own
`SITE_GRID_ID`/`SITE_HABITAT` (or `STUDY_LAT`/`STUDY_LON`) variables rather than guessing,
since this run uses per-group kernel fits (`sampling_group_col`) -- see this project's
2026-09-04 per-group curve pricing entry in `TaxaID/CLAUDE.md` before assuming a single
pooled prior table is the right join target. **Until then: no 18S smoke test exists, by
design, not as an oversight.**

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
