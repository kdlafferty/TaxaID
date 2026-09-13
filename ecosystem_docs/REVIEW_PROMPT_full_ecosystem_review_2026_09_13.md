# Review prompt -- fresh, in-depth whole-ecosystem review (written 2026-09-12 for 2026-09-13)

**Why a fresh review.** The last whole-ecosystem review is
`fable_ecosystem_review_2026-09-05.md` (findings A1-A4, B1-B5, C, D1-D3, E1-E3;
all of A and B closed by `critical_fix_review_and_changelog_2026-09-05.md` and
the 2026-09-07 commits). Since then the ecosystem has had 60+ commits, two
default-changing statistical mechanisms, three new statistical rules, six full
production runs on real data, one new workflow, one retired workflow, and a
dozen real bugs found only by running. The user is preparing the packages for
publication (USGS/WERC release plus the MEE manuscript) and wants one more
independent, skeptical pass before that. Treat this as the pre-publication
review: every finding should be either a defect, a defensibility gap, or a
"say so in the docs" item -- not a redesign wish list.

**Discipline.** Same as the 2026-09-05 review: read primary sources, do not
edit package source, produce a findings document, propose-confirm-implement.
Numbers must be read from records or derived arithmetically and labelled.
Verify purpose before flagging a "flaw" (several past findings were design
choices with documented reasons -- check the CLAUDE.md notes first). The
user is a statistician and pressure-tests with numeric hypotheticals; write
findings that survive that.

**Preconditions (check before starting).** The PtConception 12S single-site
workflow may still be running or just finished (`PtConMifishSchulte_*`,
started 2026-09-12 evening with `SCREENS_FROM_CHECKPOINT <- TRUE`); read its
session metadata and regression sentinels before treating any of its numbers
as final. All nine packages were reinstalled 2026-09-12 (TaxaExpect built
21:07 UTC, TaxaAssign 17:57, TaxaTools 17:05, TaxaMatch 09:00). Every
`devtools::check()` was 0 errors / 0 warnings at last run; TaxaAssign carries
one NOTE for a stray `README.md.bak_pre_citation_fix_20260912_131218` left by
a parallel session.

---

## 1. What changed since the 2026-09-05 review (read these first)

### 1a. Statistical mechanisms, default-changing

| Change | Where | Record |
|---|---|---|
| H1 pair-coverage floor (`min_pair_coverage = 0.8`, must equal `blast_sequences(min_query_coverage)/100`; `evaluate_likelihoods()` checks the two) and empirical-Bayes shrinkage of per-species H1 means (`shrinkage = "empirical_bayes"`, tau^2 by method of moments per dimension) -- BOTH default-on | `TaxaLikely::train_likelihood_model()`, `R/train.R`, `R/evaluate.R` | `REENTRY_PROMPT_h1_foreign_coverage_floor.md` (RESOLVED; arm table A/B/C), `TaxaLikely/CLAUDE.md` top note, supplemental methods 3B/5A. Validated on the real GL workflow lines: Lamar 593 -> 798 co-detections, precision 0.805 -> 0.818; run 2 then 0.856. |
| Regional-proximity evidence: Stage 2 GBIF fetch now uses the ecosystem's 2000-to-now window (was all time); workflows pass their `YEAR_RANGE` | `TaxaExpect::generate_regional_proximity_evidence(year_range=)` | commit d0232cd. Motivating case: a 1929 SBMNH preserved specimen of a captive siamang 74 km from Point Conception, weight 0.031 = 480x the floor, produced a species-level call from an 82%-identity match. |
| Habitat conditioning of presence evidence: `w_site = max(w * H_site, W_CLAMP)` for regional, watch-list and iNat evidence; `H_site` from the same cached LLM habitat lookup that supplies the residents' point votes | NEW `TaxaExpect::condition_evidence_on_habitat()` (9c9ea9a); `.habitat_condition()` wrapper in GL / PtCon 12S single + multi / MuguFish kernel branches | Design discussion + agreement 2026-09-12; validated on the real workflow lines: GL Lamar precision 0.856 -> 0.872 at unchanged 42/61 species and unchanged sentinels; PtCon 99.73% same consensus, water buffalo / siamang / red bat species calls gone. Table in `REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md`. |
| Downranking species reference excludes distance-clamp-only rows | all 7 workflows' `taxaexpect_species_df` | Since curve pricing every zero-record BLAST candidate has a clamp row, so "in the priors table" stopped meaning "known locally"; a genus LCA (Pseudotolithus, three plausible congeners) was narrowed to a species with posterior 0.009 and reported at the genus's 0.89. 1 of 145 downranked rows across four sites. |
| `combine_multisite_priors()` probability-scale fallback when every site's prior is J-shaped | `TaxaAssign` (2d3cdf9) | Logit rule underflowed to a mean of exactly 0 for 349 of 4,469 rows on the first real multi-site run. Logit rule kept wherever finite. Presence-mixture columns are inherited from the first site row, NOT recombined -- documented, unreviewed. |
| `score_consensus()` gains a real Jonah Ventures consensus mode; diagnostics pin the gap mode against every production workflow | `TaxaAssign` (972c197, 85d5759) -- a PARALLEL session's work, not reviewed by the session that wrote this prompt | read the commit and `diagnostics/` script before judging |

### 1b. Reference-quality screening, as actually run

- Screens rewired 2026-09-08 to `corroborate_references_locally()` -> `evaluate_reference_accessions(local_corroboration=, skip_locally_corroborated=TRUE)`; first full runs 2026-09-10/11/12.
- NCBI circuit breaker trips on every site; pending counts are large (PtCon 12S ~2,500 match / 1,866 training; 18S 3,008 / 14,407; Mugu COI 47). The workflows print INCOMPLETE banners and keep pending accessions `untested`. `inst/screen_training_references_standalone.R` finishes a training screen as a resumable overnight job; nothing equivalent exists yet for the match-candidate screen.
- Automatic removal audit (`verify_removal_candidates(screen_corroborators = TRUE)`) wired into every workflow; a removal is overturned only on positive evidence (`spared = NA` when the audit never ran). At 18S all 20 audits timed out (100-hit re-BLAST on ~1.8 kb queries) so removals stood unaudited.
- `TaxaMatch::.trim_queries_to_amplicon()` no longer errors on a marker with no registered primer pair (18S; 4a910ab).
- PtCon 12S still carries a hand override `VETO_AUDIT_SPARED <- "OQ846263"`.
- NEW `SCREENS_FROM_CHECKPOINT` switch in the 12S single-site workflow only (serves both screens from the last run's checkpoints; not yet in the other files).

### 1c. Workflow architecture

- Seven production workflows now (not eight): GreatLakes; PtCon 12S single-site, 12S multi-site (stale full file) + NEW `PtConceptionWorkflow_12S_multi_site_FAST.R` (per-Location kernel priors, real multi-site path, reuses single-site checkpoints, 1,218-sequence subset by default); PtCon 18S; `MuguFishWorkflow.R` for BOTH match sources (`MATCH_SOURCE <- "blast" | "wilder"`; `MuguWilderFishWorkflow.R` retired to `_archive_retired_scripts_2026_09_12/`). Two templates.
- All workflows: self-healing console log (`<prefix>_run_<stamp>.log`; sink + tagged `globalCallingHandlers`, re-armed per run, appends after a restart), `habitat_lookup` checkpoint, `SENTINEL_TAXA` + `regression_sentinels` in session metadata, cached LLM steps (`TaxaHabitat::build_habitat_lookup(cache_dir=)`, `TaxaFlag::review_assignments(cache_dir=)`, `TaxaTools::scientific_to_common(cache_dir=)`).
- Cache gates still test only `file.exists()` in most places (the `inputs =` staleness check exists in four workflows only).

### 1d. Run outcomes on record (all in `REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md`)

GreatLakes runs 1 and 2 (Lamar 0.805 -> 0.856), PtCon 12S single (9,113 species-rank, Girella nigricans 175), Mugu blast (517 species-rank, Fundulus parvipinnis 31 / lima 0), PtCon 18S (10,968 obs, 9,703 unprecedented, 1,640 rows / 191 taxa final -- the geographic gate, not the likelihood, governs the 18S list), PtCon 12S multi FAST (99%+ agreement with single-site), plus the two habitat-conditioning validation arms.

---

## 2. Focus areas for this review

1. **Statistical coherence of the prior side after three additions in one week.** The prior for an unrecorded candidate is now: kernel resident share, OR curve-priced evidence `theta = w * theta_present` with `w` from distance (regional), a lifted curve (watch list), iNat range (0.8), or the clamp; then `w` multiplied by `H_site`; then the soft-EM confirmation update. Check that the pieces compose (units, the budget audit `sum(w)` vs Chao, the mixture moment-matching after `H_site` scaling, whether `prior_mix_p_conc` still means what it did), that the floor at `W_CLAMP` is applied consistently between curve pricing (GL/PtCon) and blend pricing (Mugu, multi-site), and that nothing double-counts habitat (residents are already stratified by point vote; evidence rows are now scaled by the taxon-level weight -- are these the same quantity?).
2. **The two independence assumptions now load-bearing:** distance x habitat (product rule) and geographic x depth (product kernel). State where each would fail and whether any site's data is in that regime.
3. **Downranking and consensus semantics.** `.downrank_consensus()` narrows a coarse LCA to the single finer taxon the species reference knows; `consensus_posterior` on a downranked row is the COARSE rank's mass. Is that reported honestly enough (the `downranked` flag exists)? Should the narrowed species have to be among `plausible_taxa`?
4. **Sole-candidate species calls.** Red deer x9, bison, channel catfish, the triggerfish: a 100%-identity single candidate wins at posterior 1.0 regardless of prior and is flagged unprecedented. Is "flag and exclude" sufficient, or should the pipeline carry a family/genus hypothesis for every species candidate so a prior CAN move it? (The `unreferenced_genus`/`unreferenced_species` hypotheses exist for some sequences but evidently not all.)
5. **Cross-package drift.** Since 2026-09-05: `H1_Lookup$shrink_w_*`, `Stats$tau2_*`, `report_params$min_query_coverage`, `evidence$llm_parsed`, `habitat_weight`/`weight_unconditioned`/`habitat_floored`, `n_sites_combined`, `SCREENS_FROM_CHECKPOINT`, `regression_sentinels`. Check the TaxaWizard metadata JSON, the glossary, `STATISTICAL_COMPONENT_CATALOG.md`, the supplemental methods, and the READMEs against current signatures.
6. **Correctness vs. documentation.** Spot-check roxygen claims against code for every function touched since 09-05 (list: `train_likelihood_model`, `evaluate_likelihoods`, `build_habitat_lookup`, `download_gbif_occurrences` (retry/pending-key), `verify_removal_candidates`, `scientific_to_common`, `combine_multisite_priors`, `generate_regional_proximity_evidence`, `condition_evidence_on_habitat`, `score_consensus`).
7. **Known loose ends to confirm or close** (each small):
   - `generate_domestic_food_priors()` discards the iNat local-evidence boost for every domestic animal at PtCon because NCBI's `kingdom` is "Eukaryota" while iNat says "Animalia" (warning seen 2026-09-12 in the harness). Almost certainly a vocabulary-normalization gap like the 2026-08-31 Metazoa/Animalia fix -- a real, live bug candidate.
   - `combine_multisite_priors()` inherits `prior_mix_*` from the first site row (documented, not recombined).
   - `TaxaFetch::get_keys_from_context()` emits nine "Unknown or uninitialised column: usageKey/rank" warnings on every 18S run (cosmetic, but noise in the log).
   - PtCon 18S Step 10 per-`sampling_group` CSVs are dead code (`sampling_group` never reaches the consensus table).
   - `inst/TaxaID_Workflow_Template_TEST.R` has no `species_reference` (downranking) at all; the PtCon template still has the old construction pattern in one of its two evidence-free paths.
   - `PtConceptionWorkflow_12S_multi_site.R` (the full file) is stale relative to the FAST script and the single-site file; decide whether it should be retired the way the WilderFish file was.
   - Mugu's kernel branch prices evidence in blend mode with no clamp rows; the `W_CLAMP` floor there is a constant borrowed from the curve pricing.
   - `README.md.bak_pre_citation_fix_20260912_131218` in TaxaAssign (check NOTE; now gitignored).
   - `train_likelihood_model()` warns "N singleton reference(s) found but distance matrix lacks self-matches" on every real run: `build_sequence_matrix()` never emits `id_x == id_y` rows, so the self-match singleton path is dead code and the warning is noise. Decide which to remove.
   - Cache gates keyed on `file.mtime` are fooled by a re-save of unchanged content (the 2026-09-13 12S run spent 2 h 47 min re-running the outlier check because the cached raw_gbif was re-saved); the 12S single-site file is fixed, the other workflows' gates should be checked for the same pattern.
   - The evidence block costs ~40 min per run at PtCon (one GBIF tile check + fetch per zero-record taxon, 256 taxa, no per-taxon cache keyed on the year window).
   - The standalone training screen exists; the match-candidate screen still blocks a production run on NCBI.
8. **Publication readiness against the WERC criteria** (see `[[reference_usgs_werc_release_process]]` / `reference_pre_review_checklist`): pkgdown sites (none yet, flagged since June), `NEWS.md` currency per package, vignettes that are all `eval = FALSE` (three packages), CI status, licensing note on glmmTMB now that the GLMM path is archived.
9. **Performance.** The 18S match screen re-BLASTs full-length 1.8 kb queries at 100 hits in the removal audit and times out; the regional generator makes one GBIF tile check + one fetch per zero-record taxon per run (35-40 min for 256 taxa at PtCon in the harness). Both are per-run costs on a throttled service; say whether either needs a cache or a cap before release.

---

## 3. Deliverable

A findings document `ecosystem_docs/fable_ecosystem_review_2026-09-13.md` in the
2026-09-05 shape: Section A (urgent / high-confidence / small, each with a
concrete fix), Sections B-E along the focus areas above, a verdict summary,
and an explicit "closed, do not re-litigate" list carried over from the
project memory (Thread 3 reference verdicts removed by user decision; the
singleton-record rule NOT adopted; the widen-BLAST-for-unsupported-candidates
thread closed 0/22; Model D global gap withdrawn; hard habitat gate rejected
in favour of the product rule; deeper B2 redesign closed pre-publication).
Then stop and wait for the user's verdict before implementing anything.

## 4. Sources

- `ecosystem_docs/REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` (every run's numbers, both validations)
- `ecosystem_docs/REENTRY_PROMPT_h1_foreign_coverage_floor.md`
- `ecosystem_docs/fable_ecosystem_review_2026-09-05.md` and `critical_fix_review_and_changelog_2026-09-05.md`
- `ecosystem_docs/regional_evidence_sensitivity_2026_09_12.csv` (per-taxon year/habitat sensitivity, three sites)
- `ecosystem_docs/NAME_CHANGE_HISTORY.md` (2026-09-08 onward)
- Each package's `CLAUDE.md` top notes dated 2026-09-10 to 2026-09-12; `TaxaID/CLAUDE.md` top note
- Harness scripts and outputs: `GreatLakes data/REVIEW_coverage_floor_arms.R`, `REVIEW_habitat_conditioning_arms.R`, `REVIEW_lamar_score_arm.R`, `_coverage_floor_validation_2026_09_10/`; `PtConception/REVIEW_habitat_conditioning_ptcon.R`, `_habitat_conditioning_validation_2026_09_12/`
- Production checkpoints by prefix: `GreatLakes2023BurnsHarbor_`, `PtConMifishSchulte_`, `PtConMifishSchulteMultiFast_`, `PtCon18SSchulte_`, `MuguWilderFish_blast_` (and `_wilder_` if run)
- `git log --since=2026-09-05`

## 5. File hygiene done 2026-09-13 (so the reviewer does not re-find it)

- The seven production workflows are now under git, in two small local repos
  that track only `*.R` and `*.md`: `~/My Drive/Rscripts/eDNA/` (PtConception
  + SepulvedaMugu) and `~/My Drive/Stats and Data/GreatLakes data/`. Data,
  checkpoints, caches, logs and archives are ignored. The `*.bak_pre_<change>`
  backup convention is retired: future edits to those files should be
  committed there, not backed up by suffix.
- Every existing `.bak_*` file, stale `.rds.*` variant, Mugu's
  `_stale_cache_backup/` and Point Conception's superseded global-GBIF cache
  items (a 107 MB 2026-09-05 zip, its metadata and verdicts, and two
  pre-scoping `gbif_fetch_*` tables) were MOVED, not deleted, into
  `_archive_backups_and_stale_2026_09_13/` in each site directory (~205 MB
  total). Google Drive multi-parent files make `rm` unsafe here; the user
  trashes those folders from the Drive UI when ready.
- GreatLakes' raw sequencing data (5.1 GB, `correct-barcodes*`) moved to
  `~/My Drive/Stats and Data/GreatLakes raw sequencing/`; the three DADA2
  scripts' `FASTQ_DIR` updated. The analysis directory is now ~200 MB.
- Checkpoint rule adopted: save on compute, never on load. A sweep of the
  five workflows found the raw_gbif re-save (fixed) plus two harmless cases
  (`bbox`, which is deliberately re-saved under the run prefix; `model_fit`
  in the archived GLMM branch). The per-taxon LLM caches (~7,600 files,
  ~30 MB across sites) are kept as designed: content-keyed, one clear-cache
  function each.
- Still open for the reviewer: whether `institution_reviewed` and
  `geo_outlier_check` (36 MB each at PtCon 18S, derivable from raw_gbif in
  minutes) deserve their own checkpoints, and whether the 18S
  `HabitatFilteredMifish.rds` (40 MB, provenance unknown) is still used.

## 6. Corrections (2026-09-13 review)

- Mugu prices in curve mode; the blend-mode/no-clamp-row file is
  `PtConceptionWorkflow_12S_multi_site.R`.
- Workflows pass `YEAR_RANGE "1995,<year>"` (Mugu `"1990,<year>"`); only the
  package default is 2000-to-now.
- `unreferenced_genus`/`unreferenced_species` hypotheses exist for every
  query.
- The findings document is `ecosystem_docs/fable_ecosystem_review_2026-09-13.md`.
