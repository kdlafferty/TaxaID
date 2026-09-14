# Whole-ecosystem review (Fable 5.1, 2026-09-13)

Implements `REVIEW_PROMPT_full_ecosystem_review_2026_09_13.md`. Same discipline as
the 2026-09-05 review: primary sources read, **no package or workflow source
edited**, propose-confirm-implement. Numbers are read from records/code or derived
and labelled. Purpose was checked against roxygen and CLAUDE.md notes before any
"flaw" below.

Method. The coordinating session established Section 0 directly (metadata audit
run, export coverage, NEWS diff, EB estimator read). Seven parallel read-only
sub-reviews (Sonnet 5, after a spend-limit outage killed the first Fable set)
covered the focus areas; their file:line evidence is carried here verbatim where
it matters. Two high-severity cross-package claims (E1, A3) were re-verified
against source by the coordinating session before inclusion. Three premises of
the review prompt turned out to be wrong and are corrected in Section 0.6 rather
than reported as findings.

**Coordination note.** A parallel session was editing READMEs while this review
ran (`README.md.bak_20260913_1259*` in the root, TaxaMatch, TaxaLikely, TaxaAssign,
TaxaExpect and `misc review docs/`, plus `jv_comparison_table.R.bak_20260913_130057`
in the PtConception repo, all written 12:59-13:01 today under the backup convention
retired this morning). Section H's README findings were read against the files as
of ~13:40 and may be partly overtaken; re-check the affected lines before acting.

---

## 0. Established facts (do not re-derive)

### 0.1 Preconditions
- Nine packages rebuilt 2026-09-13 00:58 UTC (TaxaHabitat 06:47 UTC, commit c5af2d6).
- PtCon 12S single-site run 2 is final: `PtConMifishSchulte_session_metadata.rds`
  reads `date_run = "2026-09-13 08:39"`; sentinels Girella nigricans 175 /
  G. simplicidens 0 / F. parvipinnis 2; `n_species_rank_obs` 9,125;
  `training_screen_breaker = TRUE, pending = 1866`; `removal_audit_spared`
  empty. No `Rscript` batch process running (4 idle rsessions). Files newer than
  08:39 (`jv_*.csv`, a 10:54 log) belong to the separate JV-comparison script.
- 80 commits since 2026-09-05. GL workflow repo clean (1 commit); eDNA repo has
  `jv_comparison_table.R` modified and an untracked `CaliforniaIntertidal/`.

### 0.2 TaxaWizard structural audit (measured)
`Rscript diagnostics/taxawizard_metadata_audit.R`: 37 findings, 2 structural
(`run_llm_pipeline` metadata lists a non-existent `reference_errors` parameter;
`standardize_match_data` marks `data` required when it has a default), 35
integer-literal / vector-default formatting noise. Export coverage: TaxaTools
8/48, TaxaFetch 8/32, TaxaHabitat 6/17, TaxaMatch 25/32, TaxaLikely 11/32,
TaxaExpect 6/15, TaxaAssign 11/16, TaxaFlag 4/11 (partial by design).

### 0.3 NEWS.md currency
| Package | NEWS.md | Not yet recorded (commits since 09-05) |
|---|---|---|
| TaxaAssign | yes | 972c197 bracket mode; a691025 veto-bound cap; c92398d three bugs |
| TaxaExpect | yes | 9485592 FFT round-off; 88d8cc0 kernel-budget decision #1 |
| TaxaMatch | yes | 4a910ab 18S primer trimmer; 65a5d09 `verify_local_corroborations()`; 179c8c7; 6b9f743 |
| TaxaLikely | yes | c15f0fe; ad97447 archival; 8ffba9a 12 fixes |
| TaxaHabitat, TaxaFetch, TaxaTools | yes | current apart from minor items (08dd875; cd88846 + 26c1f42; 95020af) |
| TaxaFlag | **none** | 78dbb82 `llm_` rename + skepticism gate + `geographic_disagreement_basis`; 3f5fd8f four defects; `review_assignments(cache_dir=)` |
| TaxaWizard | **none** | 1b1af81 resync; 4aff5a1 graph design; 1ba54d8 backslash/allow-list; b69c0df lint |

All ten DESCRIPTION files: `Version: 0.1.0`.

### 0.4 EB shrinkage detection floor (coordinating session, `TaxaLikely/R/train.R:1079-1095`)
tau^2 = `max(0, var(species means) - mean(sigma^2/n_i))`, no SE reported.
`tau2_score` = 0 at GL and PtCon 12S (0.27 tau/sigma at 18S), so every species'
H1 score mean is the global mean and `calibrate_query_noise(offset_form="linear")`
falls back to the constant offset (documented warning, verified in D-B). Derived
floor: with K species means, SD of `var(means)` is about `var * sqrt(2/(K-1))`;
K = 39 at GL (402 species minus 363 singletons) gives 0.23 of the total
variance, so a true tau/sigma up to roughly 0.2-0.3 is truncated to zero about
half the time. "No between-species score signal" is an estimate at a detection
floor, not a demonstrated zero. Doc item (D-A9), not a defect; the adopted
default stands (arm C: +0.013 Lamar precision, 0 species lost).

### 0.5 Sub-review that completed in the first pass (TaxaMatch / TaxaTools)
Carried into Sections A and D: `scientific_to_common()` caches an LLM-omitted
name as a permanent "no common name" (A6); `verify_removal_candidates(
screen_corroborators = TRUE)` is a silent no-op without `cache_dir` (D-A6); four
roxygen wording items (D-A7, D-A8); the match-candidate screen has no
standalone script but IS resumable via its per-site cache (G-C3).

### 0.6 Corrections to the review prompt's premises (verified, not findings)
1. **Mugu prices in CURVE mode, not blend.** `MuguFishWorkflow.R:669`
   `USE_KERNEL_PRIORS <- TRUE`; `apply_undetected_evidence(..., pricing = "curve")`
   at `:788, :795, :804` with its own clamp rows (`:797-805`). The blend-mode
   file with no clamp rows is the stale `PtConceptionWorkflow_12S_multi_site.R`
   (`M:1430-1432` says so explicitly; calls at `M:1370, 1409, 1459` pass no
   `pricing=`). The "W_CLAMP borrowed from curve pricing" loose end therefore
   belongs to M (see F2, recommended for retirement), not to Mugu.
2. **`YEAR_RANGE` is not "2000-to-now" in any workflow.** Code is
   `"1995,<year>"` (GL:117, S:63, M:97, E:68) and `"1990,<year>"` (U:68,
   deliberate per its comment). Only the package DEFAULT of
   `generate_regional_proximity_evidence(year_range=)` is 2000-to-now; every
   workflow overrides it. Fix the sentence in the prompt/reentry doc, not the code.
3. **`unreferenced_genus`/`unreferenced_species` hypotheses exist for every
   query**, including sole candidates (`TaxaLikely/R/evaluate.R:650-682`,
   `R/unreferenced_candidates.R:144-188`; production `ratio_threshold = 0`
   at `S:1739`). The sole-candidate problem is a different mechanism (C4).
4. The full GLMM chain archival IS documented (TaxaExpect/CLAUDE.md and
   TaxaWizard/CLAUDE.md, 2026-09-09-later notes); the drift sub-review's
   "undocumented transition" item is dropped.

---

## A. Urgent / high-confidence / small

| # | Finding | Evidence | Fix |
|---|---|---|---|
| **A1** | **`PtConceptionWorkflow_12S_multi_site_FAST.R` never received the clamp-exclusion fix** the other six workflows got on 2026-09-12. Its `taxaexpect_species_df` has no `.not_clamp` step, so the Pseudotolithus-class downranking defect (genus LCA narrowed to a clamp-only species and reported at the genus's mass) is live in the one workflow that was RUN after the fix. | `F:393-395` vs `S:1857-1866` | Copy the `.not_clamp` block from S verbatim before `taxaexpect_species_df` is built. |
| **A2** | **`TaxaWizard` emits "(no params)" for every function.** `.extract_param_docs()` reads `doc$params %||% doc$parameters`; all eight metadata files use the key `"inputs"` only (grep: 0 vs 79 occurrences). The `# PARAMETER DOCUMENTATION` block fed to `phase_parameterize.md:21` is therefore always empty while `:73` tells the model "If a parameter is not listed, it does NOT exist." Verified by the coordinating session. | `TaxaWizard/R/graph.R:432, :448`; called at `:376, :641` | `doc$inputs`. Add a test asserting non-empty param docs for a known function. |
| **A3** | **Group-scope plausibility is blind to `prior_branch`.** `compute_group_priors()` sums `theta_mean` over every priors-table row matching a taxon, with no branch filter, while the candidate-scope check requires `prior_branch == "resident_observed"`. Since curve pricing every BLAST candidate has a clamp row, `consensus_has_occurrence_record` / `consensus_plausibility` can read non-unprecedented for a taxon whose only presence is a clamp or evidence row, and `review_assignments()`'s skepticism gate reads ONLY the consensus-scope columns. Same conflation the downranking fix closed, one layer up. Verified by the coordinating session; not yet cross-tabbed on a real consensus table. | `TaxaAssign/R/group_priors.R:143-148` vs `posterior_consensus.R:794-806`; callers pass unfiltered `taxaexpect_priors` at GL:1589, S:1888, E:2150, U:1121 | Filter to `prior_branch == "resident_observed"` before `compute_group_priors()` (or add an `allowed_branches` argument defaulting to that). Confirm on the PtCon 12S run-2 table: rows where `primary_plausibility == "unprecedented"` but `consensus_plausibility != "unprecedented"`. |
| **A4** | **A stale pending GBIF key loops forever.** `download_gbif_occurrences()` checks `meta$pending` before `overwrite` and reuses `dl_key`; a non-transient poll failure on an expired key is a hard `stop()` that never clears `pending`, and the retry loop re-records the same key. No code path clears it short of deleting the metadata file. | `TaxaFetch/R/download_gbif_occurrences.R:425-438, :803, :1440-1446, :1493-1522` | Clear/overwrite the pending record on a non-transient poll failure (and evict pending records older than GBIF's retention window) before erroring. |
| **A5** | **`generate_domestic_food_priors()` discards the iNat local boost for every domestic animal at PtCon.** `.norm_kingdom()` maps only Metazoa->Animalia and Viridiplantae->Plantae; NCBI's "Eukaryota" passes through, `identical()` against iNat's "Animalia" fails, `n_local` is nulled (the 9-taxon warning of 2026-09-12). Same vocabulary-gap class as the 2026-08-31 fix. | `TaxaExpect/R/generate_domestic_food_priors.R:1317-1330` | Return `NA` from `.norm_kingdom()` for superkingdom-level names and require both sides non-NA before flagging a mismatch (do NOT blanket-map Eukaryota->Animalia). |
| **A6** | **`scientific_to_common()` caches an LLM-omitted name as a permanent "no common name".** `llm_parsed = TRUE` is set for every input row of a parsed batch even when the returned name did not match (`idx` NA), then `worth_caching` includes it with `source = "none"`. | `TaxaTools/R/common_names.R:446-453, :701-711, :733, :762` | In `.parse_one_batch()` set `llm_parsed = !is.na(idx)` per row. Add a test for an omitted name. |
| **A7** | **`W_CLAMP` is a hard-coded literal duplicated in four files**, not derived from the `W_SCALE`/`D_CAP`/`D_HALF` defined 20 lines earlier. A later change to any of the three silently breaks the invariant "no row sinks below a zero-evidence taxon" (e.g. `D_CAP` 1000->1200 km leaves the floor 3.8x above the clamp price). | GL:1279 vs :1299; S:1485 vs :1503; M:1355; U:746 vs :763 | `W_CLAMP <- W_SCALE * exp(-D_CAP / D_HALF)` in all four. |
| **A8** | **GreatLakes never received the single-site cache-gate fix**: the GBIF fetch is unconditional `overwrite = TRUE` and `check_geographic_outliers()` has no gate, the exact pattern S removed ("re-fetched 100+ MB, stopped an interactive session on a menu"). | GL:515-533 vs S:421-431 | Port S's gates (`.cache_ok(inputs = raw_gbif_path)`), drop `overwrite = TRUE`. |
| **A9** | **`MuguFishWorkflow.R` invalidates every checkpoint at step >= 3 on every run.** `RERUN_FROM_STEP <- 3` with a comment claiming only two stale checkpoints are bypassed; `.use_cache()` gates on `step >= RERUN_FROM_STEP`. | U:242, U:257 | `RERUN_FROM_STEP <- Inf` (and fix the comment). |
| **A10** | **`PtConceptionWorkflow_12S_multi_site.R` `.save(raw_gbif)` sits outside its `if/else`**: on a cache hit in a fresh session `raw_gbif` is unassigned (`object not found`); in a warm session it re-saves and bumps the mtime. | M:488-518 (save at :517) | Retire the file (F2) or move the save inside the `else`. |
| **A11** | **`TaxaExpect/archive_glmm_prior_pipeline/` is not in `.Rbuildignore`** (it is only gitignored), so the 14 obsolete files ship in the source tarball and produce the "non-standard top-level file" NOTE. TaxaLikely lists its four archive dirs correctly. | `TaxaExpect/.Rbuildignore` | Add `^archive_glmm_prior_pipeline$`. |
| **A12** | **The WERC review bundle's `code.json` says `MIT`**; root `code.json`, LICENSE.md and every DESCRIPTION say CC0. The bundle is untracked, not ignored, and was edited today despite being described as frozen. | `misc review docs/code.json` (lastModified 2026-05-19) vs root `code.json` (2026-06-27) | Overwrite from root or delete; decide frozen-vs-mirror (H). |
| **A13** | **Six of nine `inst/CITATION` files cite `R package version 0.0.0.9000`** (DESCRIPTION: 0.1.0); eight of nine use `github.com/kdlafferty/TaxaID` while every README badge uses `DOI-USGS/TaxaID`; author is `person("Kevin","Lafferty")` with no middle initial vs "Lafferty, K.D." elsewhere; DOI placeholder `10.5066/xxxxxx` everywhere. | `*/inst/CITATION`; root README:558, :786 | One pass using `TaxaWizard/inst/CITATION` (already correct URL) as the template; DOI is a release blocker by nature. |
| **A14** | **`TaxaFetch::get_keys_from_context()` warnings**: tibble `$` on a column GBIF omits for `matchType = "NONE"`. Cosmetic, 9 per 18S run. | `TaxaFetch/R/get_keys_from_context.R:194, :200` | `record[["usageKey"]]`, `record[["rank"]]`. |
| **A15** | **Singleton self-match warning is dead code.** `has_self_match` is always FALSE because `.decipher_align_pairs()` drops the diagonal unconditionally; the TRUE branch is unreachable and the warning fires on every real run. Singletons actually get the `else` fallback (best foreign row, `max_foreign_score` set to the noise-floor global, gap = `max_gap_ceiling`, `rank_category = "Singleton"`). | `TaxaLikely/R/train.R:328-352`; `R/build_sequence.R:485` | Delete the check and the dead branch; `n_singletons <- length(missing_ids)` replaces the unused `df_singletons` build. |

---

## B. Prior-side statistical coherence (focus areas 1-2)

**B1. Multi-site Monte Carlo uses only the first site's presence mixture (latent, high).**
`combine_multisite_priors()` recombines `prior_alpha/beta/mean` but inherits
`prior_mix_w / theta_present / theta_absent` from the first site row
(`TaxaAssign/R/combine_multisite_priors.R:83-92`, disclosed `:154-161`).
`compute_posterior()`'s Monte Carlo path then overrides `sim_prior` from the
mixture columns alone (`compute_posterior.R:355-375`) while the deterministic
`posterior_point_est` uses the recombined `prior_mean` (`:310-311`). Hypothetical:
site A `prior_mix_w = 0.35`, site B floored at 6.36e-5; if B sorts first, presence
is drawn in ~1 of 15,000 simulations and `confidence_score` collapses for a
hypothesis whose point estimate is an order of magnitude higher. Inert today
because the FAST workflow replicates identical evidence rows across Locations
(`F:299-322`, its own "HONEST LIMIT" #2); it breaks the moment any workflow
prices evidence per site. Fix: warn/abort in `combine_multisite_priors()` when the
mixture columns differ within a group, or have `compute_posterior()` ignore the
mixture override when `n_sites_combined > 1`.

**B2. Habitat is gated twice, asymmetrically (medium, incidence unmeasured).**
Residents: hard per-record filter `hab == site_habitat`
(`estimate_kernel_priors.R:253-258`); a species whose nearby records are all
classified to another habitat produces ZERO resident rows, indistinguishable from
no records. It then enters `zero_bbox_taxa` and is priced as evidence, where the
taxon-level `H_site` applies a second, continuous discount. Hypothetical: 40
records within 2 km classified `wetland_fringe` at an `open_water` GL site: regional
`w ~ 0.049`, times `H_site` 0.2-0.4 gives `theta ~ 2e-4 to 4e-4`, two to three orders
below a `resident_observed` row. The GLMM path's habitat-mismatch promotion
(`join_priors.R:1219-1265`) is now permanently inert because the kernel path never
emits `observed_in_habitat = FALSE`. Not literal double counting of one number, but
the two compound on a classifier miss. Doc the asymmetry in `estimate_kernel_priors()`;
consider distinguishing "no nearby record" from "nearby record, wrong habitat label".

**B3. `condition_evidence_on_habitat()`'s audit columns never persist (low).**
`habitat_weight / weight_unconditioned / habitat_floored` are dropped by
`apply_undetected_evidence()`'s fresh tibble (`apply_undetected_evidence.R:925-950`);
every workflow pipes one into the other, so `taxaexpect_priors` carries no record of
how much conditioning moved a row. Left-join the three columns by `taxon_name`, or
document them as message-only.

**B4. Independence assumptions, stated failure regimes (design property).**
Distance x habitat fails where dispersal follows corridors: a GL candidate 140 km
by geodesic but 900 river-km with no overland route gets `w = 0.05*exp(-140/150)
= 0.0197`, `H_site = 0.9`, `w_site ~ 0.0177` when accessibility is near the floor;
GL is plausibly in this regime (basin connectivity is non-radial). Geographic x
depth fails for a niche that is a ridge in (distance, depth): record A 5 km / 38 m
off depth scores 0.703, record B 60 km / 1 m off scores 0.090 at lambda 25 km,
lambda_cov 250 m, favouring the depth-mismatched record 7.8x; GL is the only depth
site and has steep nearshore bathymetry. Say so in the supplemental methods.

**Verified fine.** `prior_mix_p_conc` still means what its roxygen says (never
enters `theta_new`, `apply_undetected_evidence.R:769, :893-899`). The mixture is
built from the POST-conditioning weight (conditioning overwrites `evidence$weight`
in place and precedes `apply_undetected_evidence()` in all four live workflows).
Budget audit order is correct (Chao from the resident fit only; workflow audit sums
`prior_mix_w` after every conditioning call, GL:1361-1370). 2026-09-05 A3 is fixed
and not reopened (`update_prior_from_consensus.R:531-541` re-reports sum(w)
post-refinement). `combine_multisite_priors()` mean cannot leave [min, max] of site
means on either branch; `n_sites_combined` matches roxygen. FAST's single
`SITE_HABITAT = "Marine"` for all three Locations makes replicated `H_site` rows
exact.

**Unresolved.** Noisy-OR across evidence sources (`w = 1 - prod(1-w_i)`) assumes
independent hits; whether one GBIF record can feed both the regional and the iNat
generator for the same taxon was not traced.

---

## C. Downranking, consensus semantics, sole candidates (focus areas 3-4)

**C1. `consensus_posterior` on a downranked row is the coarse mass (medium).**
`.consensus_one_observation()` computes `consensus_posterior` before
`.downrank_consensus()` runs (`posterior_consensus.R:526-549`); the helper
(`:1170-1238`) changes only `consensus_taxon / consensus_rank / is_resolved /
downranked`. The roxygen's "suitable for post-hoc confidence filtering" (`:186-187`)
is silently false on those rows. Minimal fix: one sentence in `@return`
("when `downranked = TRUE` this is the pre-downranking rank's mass; gate any
threshold filter on `downranked`"). Also `plausible_taxa` / `plausible_posteriors`
are set before downranking (`:1112-1113`) and disagree with the reported species.

**C2. Downranking never checks the narrowed species was a hypothesis for THAT
observation (medium-high).** The helper asks only whether the global
`species_ref` shows exactly one finer taxon under the coarse taxon
(`:1213-1222`), never intersecting with the row's `plausible_taxa` or the
observation's candidate set. Answer to the prompt's question: yes, require
membership in `plausible_taxa` (or at least in `posterior_df` for that
`observation_id`); otherwise stop at the coarse rank. Behaviour change, small.

**C3. The clamp-only exclusion under-scopes (medium).** All non-resident evidence
rows (`distance_clamp`, `regional_proximity`, `invasive_watch`, `inat_range`) share
`prior_branch = "resident_undetected"` (`apply_undetected_evidence.R:930-934`).
The fix excludes only `evidence_sources %in% "distance_clamp"` (exact match on a
field documented as semicolon-joined, `:330`; currently disjoint by construction,
so inert). A watch-list-only or iNat-only congener with zero local records can
still be the sole `species_ref` entry and narrow a genus LCA. Recommended:
`is.na(prior_branch) | prior_branch == "resident_observed"` in all six files plus
the template, which also aligns with A3's fix. The six production constructions
plus `TaxaID_eDNA_Workflow_Template.R:1052-1066` are otherwise identical; the
`TEST` template has none. The prompt's "old pattern in one of the PtCon template's
two evidence-free paths" could not be located (only one construction exists).

**C4. Sole-candidate species calls are a defensibility gap, not a defect.**
H2/H3 rows exist for every query (0.6.3). H2's mean is `mu1[best] - delta`, H3's
`- (delta + 2.0)` logit units (or the sqrt-mismatch equivalent), with `delta` a
marker-wide (optionally genus-specific) constant from training. At 100% identity
H1 sits at its density ceiling, so moving the call to the genus/family hypothesis
needs `prior_H2/prior_H1 ~ exp(delta)`, structurally 10^2-10^4 (not read from a
live model). No locally-plausible prior for "some other Cervidae" can outweigh a
perfect match, and arguably should not. Post-hoc flagging (`unprecedented`, TaxaFlag
review, exclusion) is the right layer, and it worked for all four cases. Doc fix:
say this in `evaluate_likelihoods()` / `posterior_consensus()` roxygen and the
methods. No code change proposed; the "singleton-record rule" stays closed.

**C5. `score_consensus(consensus_mode = "bracket")` -- independent read, verified
correct** on every sub-question: gap mode pinned against five real checkpoints
with a guard that the pre-commit extract lacks `consensus_mode`; agreement over
retained HITS (`score_consensus.R:630-635`) as JV wrote it; exclusive lower bound
disclosed (1 ESV of 14,719, `bracket_width` escape hatch); tie at the bar returns
NA; widening condition at `:660-669`; the false GITA/JV attribution removed
(`:9-35, :101-127`); the three JV ambiguities are one parameter and two disclosed
hard-coded choices; rank walk finest->coarsest; NA taxonomy counts in the
denominator only. Column set identical between modes (`:719-733`;
`bracket_width_used`, `agreement_achieved` always present, NA in gap mode). TaxaFlag
reads nothing from `score_consensus()` output. Undocumented `report_params`
attribute (D-A5). Doc gaps in the catalog and NEWS (E, 0.3).

---

## D. Correctness vs documentation and loose ends (focus areas 6-7)

### D-A. Findings
| # | Function | Finding | Evidence | Fix |
|---|---|---|---|---|
| D-A1 | `save/apply_spatial_review_decisions()` | Seeding without `before=` marks every non-NA `main_habitat` as a reassignment ("conservative reading"), so a seeded confirmation freezes the automatic habitat forever, the bug c5af2d6 meant to fix. The seeding script lives outside the repo; probable, not certain. | `TaxaHabitat/R/spatial_review_decisions.R:62-70, :113-133` | Rebuild `before` from a fresh `flag_habitat_inconsistencies()` pass when seeding, or accept and document the seam with an age-based re-review trigger. Also: reapplied `spatial_flag`/`main_habitat` are never re-validated against a drifted automatic classification (document as a limitation). |
| D-A2 | `build_habitat_lookup()` | A chunk whose LLM output fails the character/non-empty gate contributes ZERO rows (contradicts "one row per unique taxon"); a total `prompt_api()` failure discards already-computed cache hits. | `TaxaHabitat/R/build_habitat_lookup.R:182-215`, roxygen `:72-75` | NA-shaped frame for `to_call` on the unusable branch; `tryCatch` around `prompt_api()`. |
| D-A3 | `train_likelihood_model()` | `@return` `Stats` block lists 6 fields; the object carries 16 (`n_anchors, shrinkage, tau2_*, min_pair_coverage, n_self_fallback, n_foreign_unqualified, mlr_violations, max_ceiling_z*`). | `R/train.R:655-680` vs `:1394-1409` | Complete the block. |
| D-A4 | `evaluate_likelihoods()` | The pair-coverage check is one-directional with 0.01 tolerance and undocumented in its own roxygen; `train_likelihood_model()`'s `@param` reads as symmetric. | `R/evaluate.R:1851-1876, :1406`; `train.R:544-551` | Short `@section` + reword. |
| D-A5 | `score_consensus()`, `download_gbif_occurrences()` | Both set an undocumented `report_params` attribute; `served_from_cache_after_failure`/`capped_keys` documented only in `@param` prose. | `score_consensus.R:531-539`; `download_gbif_occurrences.R:983-989` | `@section Attributes`. |
| D-A6 | `verify_removal_candidates()` | `screen_corroborators = TRUE` (default) is a silent no-op when `cache_dir = NULL` (default); all production callers pass `cache_dir`. | `TaxaMatch/R/reference_label_verdict.R:987-995, :1275` | Warn when `screen_corroborators && is.null(cache_dir)`. |
| D-A7 | `verify_removal_candidates()` | `@return` says `spared` is boolean (NA case only in a code comment); corroborator columns documented as conditional but always present; zero-candidate `empty` frame lacks them (schema differs 0-row vs >0-row); `@param` says any non-"keep" corroborator is surfaced but "untested" is excluded. | `:1114-1123, :1176-1183, :1263-1269, :1350-1352` | Doc + add the six columns to `empty`. TaxaWizard metadata copies the "spared (logical)" text (E). |
| D-A8 | `scientific_to_common()` | Description says `use_llm = TRUE` is the default (it is FALSE, `:647`); "single batched call" is 20-name batches. | `TaxaTools/R/common_names.R:557-558, :585-587, :373-374` | Wording. |
| D-A9 | `train_likelihood_model()` | tau^2 reported without an SE or detection floor (0.4). | `train.R:1079-1095` | Report the floor (or a bootstrap SE) in `Stats`; note in `calibrate_query_noise()` that `"linear"` is moot when `tau2_score = 0`. |

### D-B. Verified fine (roxygen = code, Rd usage = formals)
`train_likelihood_model` (floor semantics, EB estimator, anchor exclusion, <3-species
fallback, new columns), `evaluate_likelihoods` (check logic, 0-100 normalisation),
`calibrate_query_noise` (documented fallback warning at `R/calibrate_query_noise.R:462-475`),
`build_habitat_lookup` (cache key verified on read, unresolved never cached),
`download_gbif_occurrences` (submit/poll retry, `on_submit_failure`),
`combine_multisite_priors`, `generate_regional_proximity_evidence` (`year_range`
threaded to Stage 2 at `:323`), `condition_evidence_on_habitat` (`w_floor` is
caller-supplied, source-agnostic), `score_consensus`, `verify_removal_candidates`
(NA logic, zero NCBI calls when nothing is "remove", `still_saturated` defensible),
`scientific_to_common` (cache key, explicit nulls cached, unparseable batches not).

### D-C. Loose ends (prompt section 7) -- disposition
| Loose end | Disposition |
|---|---|
| Domestic priors Eukaryota/Animalia | Live bug, A5. |
| `combine_multisite_priors()` prior_mix inheritance | Latent defect with a consumer, B1. |
| `get_keys_from_context()` warnings | A14. |
| PtCon 18S Step 10 per-`sampling_group` CSVs | Confirmed dead (F5): `sampling_group` exists only on `occurrences_clean` (E:802); `any_of()` at E:2646 drops it; loop at E:2658-2666 runs zero times. |
| TEST template lacks `species_reference`; PtCon template old pattern | First confirmed; second not found (C3). Both templates call archived GLMM functions unguarded (F7). |
| Retire `PtConceptionWorkflow_12S_multi_site.R` | Yes (F2). |
| Mugu W_CLAMP "borrowed" | Premise wrong (0.6.1); the hard-coded literal is A7. |
| `README.md.bak_pre_citation_fix_*` NOTE | Disk hygiene; gitignored; plus new `.bak_20260913_*` files from a parallel session today. |
| Singleton self-match warning | A15. |
| mtime cache gates in other workflows | GL has no gate (A8); M re-saves (A10); Mugu re-saves `lik_result` unconditionally (F4); S and E fixed. |
| Evidence block ~40 min | G-C2: Stage 1 tile check has no cache at all. |
| Match-candidate screen standalone | None exists; resumable via per-site cache by re-sourcing to that step; a ~10-line variant of the training script reading `match_obj_restored` would do (Mugu has no such checkpoint). |

---

## E. Cross-package drift: TaxaWizard, TaxaFlag, shared docs (focus area 5)

### E1. TaxaWizard (the user's first question: what needs updating)
Tier 1 = a generated workflow would break or silently reproduce a fixed defect.

| # | Tier | Item | Evidence |
|---|---|---|---|
| E1.1 | **1** | Parameter docs always empty (A2). | `R/graph.R:432` |
| E1.2 | 1 | `occ_to_std.R` runs the UNCACHED habitat step (`build_habitat_prompt` -> LLM loop -> parse); no snippet calls `build_habitat_lookup()` although it is in `TaxaHabitat.json`. Reproduces the verdict-flip instability that cost 0.05 Lamar precision. | `inst/graph/snippets/occ_to_std.R:22-37` |
| E1.3 | 1 | `post_to_consensus.R` passes no `species_reference` and never calls `add_slash_taxon()`; if a user adds a species reference by hand from the README they get the pre-fix pattern. `update_prior_from_consensus()` is called by the snippet but absent from `TaxaAssign.json`. | `post_to_consensus.R:34` |
| E1.4 | 1 | `run_llm_pipeline` metadata lists a phantom `reference_errors` parameter (would emit an "unused argument" call). | `TaxaAssign.json` |
| E1.5 | 2 | `std_to_priors_kernel.R` has no evidence block; `condition_evidence_on_habitat`, all five `generate_*_evidence` functions, `fit_regional_presence_curve`, `kernel_budget_sensitivity` are absent from `TaxaExpect.json` (`apply_undetected_evidence` is present, uncalled). Decide: gated extension of the kernel edge, or a prompt statement that the wizard does not offer it. | `std_to_priors_kernel.R` |
| E1.6 | 2 | `TaxaMatch.json` `blast_sequences` lacks `min_query_coverage` (default 80), the parameter that must equal `train_likelihood_model(min_pair_coverage)*100`; `matrix_to_model.R` hard-codes 0.8 with a comment. | `TaxaMatch/R/blast_sequences.R:375` |
| E1.7 | 2 | `TaxaAssign.json` `score_consensus` has no `consensus_mode / agreement_fraction / bracket_width / bracket_fallback / whitelist`. | |
| E1.8 | 2 | `TaxaFlag.json` `review_assignments` lists 11 of ~30 inputs: no `cache_dir`, none of the skepticism-gate columns (`consensus_plausibility_col` etc.), `use_candidates`, `irreducible_only`. `consensus_to_reviewed.R` passes no `cache_dir`. `add_posthoc_assessment` entry is current. | |
| E1.9 | 2 | `standardize_match_data` `data` marked required (has a default); `verify_removal_candidates` output text "spared (logical)"; `train_likelihood_model` output text omits `shrink_w_*`/`tau2_*`. | |
| E1.10 | 2 | Absent from metadata: `verify_local_corroborations`, `score_reference_labels`, `refine_reference_verdicts` (TaxaMatch); `save/apply_spatial_review_decisions`, `review_spatial_flags`, `flag_habitat_inconsistencies` (TaxaHabitat); `add_slash_taxon`, `adjust_inat_range_priors` (TaxaAssign); `scientific_to_common` (TaxaTools); `flag_watch_candidates`, `build_review_covariates`, `check_gbif_tile_range`, `compute_local_occurrence_distance`, `review_spatial_context` (TaxaFlag). | |
| E1.11 | 2 | Prompt falsehoods: `phase_parameterize.md:97` explains `search_radius_deg` in terms of grid cells, habitat slopes and Moran eigenvectors (archived GLMM chain); `phase_path_select.md:53` describes the wrapper path as "GBIF fetch + habitat + grid + priors". `R/shiny.R:1524`'s help text for the same parameter is correct. | |
| E1.12 | 2 | `lik_prior_to_post_multisite.R` comment describes only the logit rule (now has the probability-scale fallback; B1 applies to any per-site pricing). | |
| E1.13 | -- | Metadata `output` fields are never read at runtime (only `inputs`), so stale output text is documentation-only. `REENTRY_PROMPT.md` (Session 73, names deleted edges) is `.Rbuildignore`d; archive it. No NEWS.md. No test asserts that every function named in a snippet or in `workflow_graph.json` exists in the installed package -- add one (plus the A2 param-doc assertion). | `R/graph.R`, `R/engine.R`, `R/context.R` |

### E2. TaxaFlag (the user's second question)
| # | Item | Evidence / disposition |
|---|---|---|
| E2.1 | **Skepticism gate can be suppressed by clamp/evidence rows** via the branch-blind group prior (A3). The fix is upstream in TaxaAssign, not in TaxaFlag. | `review_assignments.R` reads only `consensus_*_col`; no `primary_*_col` exists |
| E2.2 | `check_gbif_tile_range()` has no `cache_dir` and no cache; it is Stage 1 of the regional generator, called once per zero-record taxon per run (G-C2). | `TaxaFlag/R/check_gbif_tile_range.R:154-161`; `generate_regional_proximity_evidence.R:301` |
| E2.3 | `review_assignments(cache_dir=)` key hard-codes `"v1"` and hashes `taxa_info` columns but not the GUIDELINES prompt text or model identity; the 09-07 gate happened to add columns (invalidating old entries by luck). A wording-only prompt change would replay stale verdicts. | `review_assignments.R:726-733` |
| E2.4 | No renamed/removed upstream column is read by any TaxaFlag function; `prior_branch / evidence_sources / habitat_weight / n_sites_combined` are read nowhere (only matters via E2.1). Bracket-mode output changes nothing TaxaFlag consumes. `flag_watch_candidates()` deliberately compares raw scores and is orthogonal to habitat-conditioned watch evidence (optional roxygen note that `H_site` shrinks the prior-side weight further). | grep |
| E2.5 | Docs: `llm_` names consistent across README, vignette, inst docs (unprefixed names in `inst/run_all_functions.R:190-192` are the LLM's own JSON schema, intended). No NEWS.md (entries needed: 78dbb82, 3f5fd8f, 5ae5559). README's "three independent checks" omits 7 of 11 exports; one example comment carries a fix date (`README.md:155`). The three `REENTRY_PROMPT_*.md` at the package root are closed (2026-07-26..30), `.Rbuildignore`d, and archive candidates; `TaxaAssign/R/posterior_consensus.R` has a live comment pointing at the axis2 one (fix the pointer first). | |

### E3. Shared documents
- **`NAME_CHANGE_HISTORY.md` is missing every 2026-09-12/13 package change**:
  `score_consensus(consensus_mode=)`, `condition_evidence_on_habitat()` + its
  columns, `combine_multisite_priors()` fallback + `n_sites_combined`,
  `generate_regional_proximity_evidence(year_range=)` default,
  `save/apply_spatial_review_decisions()`, `scientific_to_common(cache_dir=)` +
  `taxatools_clear_cache()`. The 09-10 items (floor, EB, habitat cache) ARE logged.
- `STATISTICAL_COMPONENT_CATALOG.md` / `SOUNDNESS_REVIEW.md`: `score_consensus`
  (catalog :52) has no bracket-mode row; `combine_multisite_priors` (:50/:116) lacks
  the fallback that fired on 7.8% of rows (349/4,469) on the first real run;
  `condition_evidence_on_habitat()` and the spatial-review cache are uncatalogued.
  Nothing contradicts a current default.
- Glossary: fine; nothing new is a term collision. `llm_parsed` is an internal column
  and need not be logged.
- Stale "8 workflows": `REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md:398`;
  `REENTRY_PROMPT_workflow_structure_audit.md:153` and `AQUARIUM_BENCHMARK_DESIGN.md:35`
  still cite `MuguWilderFishWorkflow.R` as live. Root `CLAUDE.md` "Licensing" and
  `LICENSE.md` still carry the glmmTMB/GPL caveat although glmmTMB is in no DESCRIPTION.
- `TaxaAssign/inst/INTRO.md` and `TaxaTools/inst/INTRO.md` say "a suite of four R
  packages". `TaxaMatch/inst/reference_accession_evaluation_guide.md` cites a
  nonexistent `REENTRY_PROMPT_flagged_accession_second_look.md`.
- Archived functions are never described as live in any README; `ECOSYSTEM_WORKFLOW.md`'s
  archived-pathway banners are the model.

---

## F. Production workflow files (focus 1c, 7)

| # | Finding | Evidence | Fix |
|---|---|---|---|
| F1 | A1, A7, A8, A9, A10 above. | | |
| F2 | **Retire `PtConceptionWorkflow_12S_multi_site.R`.** Not run since 2026-07-13; blend-only pricing; A10; a hard-coded cross-workflow `readRDS(".../PtCon18SSchulte_bbox.rds")` with no guard (M:477). It does carry sentinels, log, conditioning, decisions cache, so it is superseded rather than missing features. | F:8 header; `PtConMifishSchulteMulti_*` mtimes | Move to `_archive_retired_scripts_2026_09_1x/` with a README, as for WilderFish. |
| F3 | **PtCon 18S has no habitat conditioning and no spatial-review step.** Domestic/watch/GISD/iNat evidence is priced (E:1080-1208) without `H_site`; GISD is not distance-gated (Rapana venosa at 3,933 km, E:1126-1127). `review_spatial_flags()` is commented out (E:785-788); `filter(spatial_flag == "likely")` runs unreviewed with no decisions cache. May be deliberate marker choices; confirm rather than fix silently. | grep: zero hits for `.habitat_condition`/`W_CLAMP` in E | User decision. |
| F4 | `MuguFishWorkflow.R` re-saves `lik_result` unconditionally after a cache hit, so the mtime `.match_src_newer` compares no longer means "last recomputed". Mugu also has no INCOMPLETE banner and no session metadata; `RUN_ACCESSION_SCREEN <- FALSE` is the committed default, so likelihoods train on unscreened references with one console line. | U:1613-1615, U:1523-1524, U:240, U:1474-1477 | Gate the save; add the banner/metadata block. |
| F5 | 18S Step 10 dead code (D-C). | E:802, E:2646, E:2658-2666 | Recompute `sampling_group` on `accurate_precise_consensus`'s own taxonomy (the `case_when` at E:803-887) or delete the loop. |
| F6 | `SCREENS_FROM_CHECKPOINT <- TRUE` is S's committed default (S:48): a fresh run freezes the 1,866-pending training screen rather than chipping at it. Porting to GL/E/M is near copy-paste (checkpoint paths exist at GL:1072-1189, M:1115-1250, E:1731-1870); Mugu needs per-marker adaptation. | | Decide the default; port after. |
| F7 | Both templates call archived GLMM functions unguarded (`optimize_grid_size`, `create_sites_from_grid`, `prepare_model_dataframe`, `plot_theta_map_interactive`; TA:939-1137, TB:600-672) and hard-code `YEAR_RANGE <- "1995,2025"` (TA:163, TB:61). | | Wrap in the production `USE_KERNEL_PRIORS` notice or delete; compute the end year. |
| F8 | 18S `SENTINEL_TAXA` is `character(0)` (E:47). No taxon in the script's own text qualifies; the two highest species-rank taxa of the 2026-09-12 run's consensus table are the natural candidates, chosen from the run record not the script. | | User picks. |
| F9 | `institution_reviewed` is write-only in every workflow (36 MB at 18S; GL:733 load commented out); `geo_outlier_check` is a genuine gate worth keeping (GBIF rate limiter at ~360 keys, E:544-547). `HabitatFilteredMifish.rds` (40 MB): zero references in any `.R` file across both repos and TaxaID; orphaned. | | Drop or trim the first; keep the second; archive the third after a manuscript-figure check. |
| F10 | Hygiene: ~23 `.bak*` files outside archive dirs, including today's post-retirement set (see Coordination note); `GreatLakes data/stale_pre_combined_reblast_backup_20260803_112250/` missed by the sweep; scattered absolute paths (E:141, E:615, U:555, S:637, E:928). | | Relocate via Drive UI; cosmetic path cleanup optional. |

**Verified fine.** Console-log block byte-identical across all nine files.
`.habitat_condition()` + `W_CLAMP` verbatim-identical in GL/S/M/U (U's shared
`"MuguWilderFish_habitat_cache"` is deliberate). Removal-audit gating consistent;
`spared` never TRUE without a positive verdict; 18S's 20 timeouts leave NA (designed).
`SCREENS_FROM_CHECKPOINT` falls back to a live screen when a checkpoint is absent.
Archived-function mentions in GL/S/M/E/U are comments or inside labelled dead branches.
`YEAR_RANGE` reaches both the GBIF fetch and the regional generator in every file
with an evidence block.

---

## G. Publication readiness and performance (focus areas 8-9)

### G-A. Readiness against the WERC checklist
| Item | State | Action |
|---|---|---|
| pkgdown | Real built sites for all 8 core packages in `pkgdown_sites/` (gitignored), dated 09-07/09-10; no `_pkgdown.yml` anywhere; sites predate `condition_evidence_on_habitat()` and bracket mode. | Re-run `ecosystem_docs/build_pkgdown_sites.R` after the code freeze; decide hosting (gitignore comment says "migrating to GitLab"). |
| NEWS.md | 0.3. | TaxaFlag and TaxaWizard need files; four others need the 09-07..12 entries. |
| Vignettes | **Six of nine packages have vignettes that are entirely `eval = FALSE`** (Fetch, Habitat, Match, Likely, Expect, Flag); Tools and Assign evaluate; Wizard has none. R CMD check never executes six packages' example workflows (one rot incident already, 2026-09-03). | Evaluate at least one chunk per vignette on a bundled fixture, or state the policy. |
| CI | One `R-CMD-check.yaml`, matrix over 9 packages, `error_on = "error"` (NOTEs/warnings never fail). Run history not checkable offline. | Consider `error_on = "warning"` for release. |
| Licensing | CC0 uniform; glmmTMB absent from every DESCRIPTION; root `CLAUDE.md` and `LICENSE.md` caveats stale; review-bundle `code.json` says MIT (A12). | A12 + two one-line deletions. |
| CITATION / DOI | A13. | |
| DESCRIPTION | No `URL:`/`BugReports:`/`Date:` in any package; `Depends: R (>= 4.1.0)` in three packages only. `rlang` shows zero `rlang::` uses in TaxaFetch/TaxaAssign/TaxaFlag (may be `@importFrom`; unverified). | Standardise; NAMESPACE-aware import check. |
| Shipped placeholder | `inst/README.md` at the TaxaID root is an unfilled WERC template ("ADD SOFTWARE TITLE", `Last, F.M.`, Python 3.8.5 dependency, broken `media/` links, 4-x DOI); the root has its own DESCRIPTION/NAMESPACE, so it would ship. | Fill in or `.Rbuildignore`. |
| Review bundle | `misc review docs/` untracked, not ignored, described as frozen, edited today; its README cites `flag_reference_errors`, `train_biodiversity_model`, `build_priors`, `generate_full_priors`, `plot_theta_map_interactive` as current, `build_reference_matrix()` (never existed), and inventories off by 3x. | If the WERC submission has not gone out: regenerate from root. If it has: freeze, gitignore, exclude from global edit passes. |

### G-B. Cleanup of 2026-09-05 items
A1-A4 and B2 closed (per `critical_fix_review_and_changelog_2026-09-05.md`,
2026-09-07 commits, and B "verified fine"). B5's infinite-TTL local corroboration
and C's glossary are done. E1 (whole-set MSA / full-population screening scaling)
remains architectural and is now measurable: 18S 14,407 pending training
accessions, 3,008 pending match accessions.

### G-C. Performance
1. **18S removal audit.** `audit_max_hits` default 100; no query-length cap
   below `max_query_len` (marker-aware when primers resolve, else 5,000 bp); 18S has
   no registered primer pair (by design) so 1.8 kb queries go to BLAST at full
   length and time out. Recorded safely as `spared = NA`. Not a correctness issue;
   a lower `audit_max_hits` for unprimed markers before the next 18S run stops
   guaranteed-timeout NCBI calls. (`reference_label_verdict.R:1154-1195`;
   `evaluate_reference_accessions.R:2106-2126`)
2. **Regional evidence, ~40 min/run at PtCon.** Stage 1 `TaxaFlag::check_gbif_tile_range()`
   is a live HTTP tile-density request per taxon with `escalate = TRUE` adding
   coarser-zoom requests on a miss, and has NO cache (E2.2). Stage 2
   `TaxaFetch::get_gbif_occurrences(cache_dir=)` is cached. Build a per-taxon cache
   keyed on (taxon key, rounded lat/lon, buffer, zoom) for Stage 1 (year-agnostic:
   the tile API is not year-filterable) and record the Stage 2 summary alongside,
   keyed additionally on `year_range`. **Before release**: it is a recurring cost on
   a throttled service and blocks the "test fast before full" rule.
3. Match-candidate screen: resumable via cache; standalone would be ~10 lines (D-C).

---

## H. README review (all 13 files)

Cross-cutting: DOI placeholder `10.5066/xxxxxx` in every citation block; org split
(`DOI-USGS` in all nine package badges vs `kdlafferty` in root README:558/:786 and
eight CITATION files); the Wilkinson et al. 2018 author-order fix (79b19c0) is
complete (only root README and the presentation cite it; the TaxaMatch/TaxaLikely
`.bak_pre_citation_fix` files are red herrings). `README.html` is stale but
gitignored. `ecosystem_docs/readmes/*.pdf` (2026-06-09) are three months stale;
`render_readmes.R` hard-codes an RStudio-bundled pandoc path and strips `<img>`
tags, so TaxaExpect's new figure would vanish from a regenerated PDF.

| README | Line | Problem | Fix |
|---|---|---|---|
| root | 723, 726 | `run_bayesian_pipeline(..., site=)` / `run_llm_pipeline(..., site=)`: no `site` formal; both omit the required `backbone_id`. | Real argument names + `backbone_id = 11`. |
| root | 866-874 | Inventory counts stale: TaxaTools 47 (48), TaxaHabitat 13 (17), TaxaExpect 14 (15). | Update. |
| root | -- | No mention of any 09-10..13 mechanism. | One line each in the package-purpose prose. |
| root | 652-653 | `inst/workflow_fastq_to_match.R` etc. lack the `TaxaMatch/` prefix. | Prefix. |
| TaxaTools | 24-26 | `convert_taxonomy_backbone()` attributed to TaxaTools (it is TaxaMatch's; TaxaTools' analog is `change_backbone()`). Provider table omits `call_azure_openai_api()`; six exports unmentioned. | Fix; add. |
| TaxaFetch | 45-46, 49-52 | `make_bbox_wkt(lat_min=...)` (real: `lat, lon, radius_deg`) and `get_keys_from_context(c(...), backbone_id=)` (real: `hierarchy_df`) both error as written. No iNaturalist row; 13 of 32 exports unmentioned. | Fix examples; add iNat + geo-screening. |
| TaxaHabitat | -- | `save/apply_spatial_review_decisions()`, `flag_institution_candidates()`, `review_institution_flags()` absent. | Add a subsection. |
| TaxaMatch | 57-58 | `filter_sequences(min_reads=)` (real: `min_abundance`) errors. `:171` `TaxaLikely::fetch_reference_recordings()` does not exist (`fetch_xc_recording_locations()`). `:238` dead link `inst/animl_workflow_design.md`. `verify_removal_candidates()` undocumented; the site pipeline (`build_site_table`, `assign_spatial_group`, `group_observations_by_bbox`, `join_event_site_metadata`, `add_lowest_consistent_rank`, `match_driving_accessions`) and `verify_local_corroborations()` unmentioned. | Fix; add. |
| TaxaLikely | 316, 324, 351 | Session numbers and a CLAUDE.md pointer in user docs. | Strip. |
| TaxaExpect | 27 | "species distribution models ... TaxaExpect is one such method" contradicts the compositional framing at :51-54. `fit_regional_presence_curve`, the three evidence generators and `year_range` absent. | Reword; add. |
| TaxaAssign | 105-108 | `score_consensus()` bracket mode undocumented (no stale JV language present); `combine_multisite_priors()`, `add_slash_taxon`, `adjust_inat_range_priors`, `compute_group_priors` unmentioned. | Add. |
| TaxaFlag | 14-16, 33-37, 155 | "three independent checks" omits 7 of 11 exports; fix-date comment in an example. | Scope the claim; drop the date. |
| TaxaWizard | -- | Clean; graph JSON contains none of the deleted edge ids. | -- |
| inst/README.md | all | Unfilled WERC template (G-A). | Fill or exclude. |
| diagnostics/fast_workflows | all | Session narrative; dev tooling, low priority; all files/functions exist. | Prune only if shipped. |
| misc review docs | 250, 360-364, 412-472 | See G-A; plus broken relative links from the subdirectory. | Regenerate or freeze. |

Verified fine: no README references any archived function or the retired Mugu
script as live; `TaxaAssign::suggest_unreferenced_species` correctly described as a
forwarder; every spot-checked formal exists as documented for the 09-10..13
functions; DESCRIPTION `Authors@R` consistent.

---

## I. Stale documents (archive candidates)

Archive convention: commit e6e3803 (2026-09-07) `git rm`'d 22 closed docs and relies
on history; there is no `ecosystem_docs/archive/`. Recommend the same.

| Path | Tracked | Class | Action |
|---|---|---|---|
| `ecosystem_docs/SESSION_A_reentry_prompt.md` (05-27) | yes | stale | git rm |
| `ecosystem_docs/DATA_TYPE_AUDIT_PLAN.md` (05-27) | yes | plan never implemented | git rm |
| `ecosystem_docs/refactor_unified_likelihood_pipeline.md` (06-02) | yes | PLANNED, zero citations | git rm |
| `ecosystem_docs/CONSENSUS_METHODS_COMPARISON.md` (05-31) | yes | superseded by bracket mode | git rm |
| `ecosystem_docs/SPEC_plot_theta_surface.md`, `SPEC_supplemental_methods_kernel_rewrite.md` | yes | shipped; zero live citations | git rm |
| `ecosystem_docs/REENTRY_PROMPT_h1_foreign_coverage_floor.md` | yes | RESOLVED; cited from `TaxaLikely/R/train.R` | keep until the roxygen carries the arm table, then git rm |
| `ecosystem_docs/REENTRY_PROMPT_taxawizard_metadata_resync.md` | yes | CLOSED | git rm (record is in TaxaWizard/CLAUDE.md) |
| `ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md` | yes | decisions 2+4 built, 1 resolved, 3 not built by decision | git rm after a one-line closure note in the catalog |
| `ecosystem_docs/REENTRY_PROMPT_workflow_structure_audit.md` | yes | status ambiguous (spun off as open work 09-06; item 118 left undone) | user confirms |
| `ecosystem_docs/LAYER1_WORKFLOWS.md` (07-02) | yes | says "7 of 8 packages" | update or git rm |
| `ecosystem_docs/readmes/*.pdf` (06-09) | yes | stale renders | regenerate before release |
| `TaxaFlag/REENTRY_PROMPT_axes_wrapup.md`, `..._axis2_...md`, `..._posthoc_...md` | yes | closed 2026-07-26..30 | fix the `posterior_consensus.R` comment pointer, then git rm |
| `TaxaWizard/REENTRY_PROMPT.md` (Session 73) | yes | names deleted edges | git rm |
| `TaxaAssign/inst/PRIOR_LIKELIHOOD_MATCHING.md` (04-01) | yes | predates the posterior_consensus rewrite | verify content, then decide |
| `TaxaAssign/inst/INTRO.md`, `TaxaTools/inst/INTRO.md` | yes | "four R packages" | fix content |
| `misc review docs/` | untracked, not ignored | see G-A | decide |
| `Claude outputs/theta_surface.png` | ignored | duplicate of `TaxaExpect/man/figures/` | delete |
| `presentation_analyses/` (05-28) | ignored | no citations | leave or delete |
| root `PtCon18SSchulte_occurrences_{clean,std}.rds` (86 MB), `TaxaID_test_*.rds` | ignored | zero citations | local cleanup optional |
| `README.html`, `*.bak_*` | ignored | -- | leave; today's new `.bak` files: stop the writer |
| Keep as LIVE / CLOSED-KEEP: `REENTRY_metadata_driven_blank_detection.md`, `coverage_likelihood_literature.md`, `TaxaLikely_theory_context_brief.md` (hard-link twin not inside the repo), `POSITIVE_CONTROLS_design_options.md`, `AQUARIUM_BENCHMARK_DESIGN.md`, `TODO_validation_benchmark.md`, `session_notes/*`, the two 2026-09-05 review docs, `regional_evidence_sensitivity_2026_09_12.csv` (ignored), `install_all.R`, `load_all.R`, `build_pkgdown_sites.R`, `GL_presentation/`. | | | |

---

## Verdict summary

| # | Finding | Severity / confidence | Size |
|---|---|---|---|
| A1 | FAST multi-site workflow lacks the clamp-exclusion fix | High / high | Tiny |
| A2 | TaxaWizard parameter docs always empty (`doc$params` vs `"inputs"`) | High / high (verified) | One line + test |
| A3 | Group-scope plausibility branch-blind; skepticism gate suppressible | High / high mechanism, incidence unmeasured | Small |
| A4 | Stale pending GBIF key loops forever | High / high | Small |
| B1 | Multi-site MC posterior uses first site's mixture only | High latent / high (inert today) | Small guard |
| A5 | Domestic priors kingdom mismatch (Eukaryota) | Medium / high | Small |
| A6 | `scientific_to_common()` caches omitted names as "none" | Medium / high | One line |
| A7-A10 | W_CLAMP literal; GL no cache gate; Mugu RERUN_FROM_STEP; M raw_gbif save | Medium / high | Tiny each |
| C2, C3 | Downranking ignores the observation's candidate set; exclusion under-scoped | Medium-high / high | Small |
| C1 | `consensus_posterior` on downranked rows is the coarse mass | Medium / high | Doc |
| C4 | Sole-candidate species calls | Defensibility gap / high | Doc |
| B2 | Double habitat gating on classifier misses | Medium / medium | Doc + design note |
| D-A1 | Spatial-review seeding freezes automatic habitats | Medium-high / medium | Small |
| E1 | TaxaWizard: uncached habitat snippet, no species_reference, no evidence block, metadata gaps | Medium / high | Medium |
| E2.3 | `review_assignments` cache key omits prompt text | Low-medium / high | Tiny |
| E3 | NAME_CHANGE_HISTORY missing all 09-12/13 changes; catalog stale | Medium / high | Small |
| F2, F3 | Retire stale multi-site file; 18S lacks conditioning + spatial review | Medium / user decision | -- |
| A11-A13, G-A | Buildignore, MIT code.json, CITATION versions/URL/DOI, vignettes all eval=FALSE, placeholder inst/README | Release blockers / high | Small each |
| G-C2 | Uncached GBIF tile check, ~40 min/run | Medium / high | Small |
| H | README: 4 examples that error as written, stale counts, missing mechanisms | Medium / high | Medium |
| I | 14 archive candidates | Low | -- |

Nothing here contradicts the validated real-data results (Lamar 0.872 at 42/61
species, PtCon 99.48% run-to-run agreement, the bracket-mode 14,718/14,719).
The findings again concentrate where mechanisms meet: a fix applied in six files
but not the seventh (A1), a filter applied at candidate scope but not group scope
(A3), a value recombined on one code path but not the other (B1), a key the code
reads under one name and the data supplies under another (A2).

## Closed, do not re-litigate
- Thread 3 reference-quality verdicts: removed by user decision, do not rebuild.
- Singleton-record rule: NOT adopted without a sensitivity check; triggerfish
  (and now red deer, bison, channel catfish) acceptable as flagged (C4).
- Widen-BLAST-for-unsupported-candidates: closed, 0/22 ever hit max_hits.
- Model D global gap: withdrawn; EB shrinkage adopted (arm C).
- Hard habitat gate: rejected in favour of the product rule
  `w_site = max(w * H_site, W_CLAMP)`.
- Deeper B2 (mixture-update) redesign: closed pre-publication; veto-bound cap
  confirmed sufficient.
- 2026-09-05 A1-A4: closed by the 2026-09-07 commits.
- `compute_likelihoods()` / `model_likelihoods()` archival; `suggest_unreferenced_species`
  placement: resolved 2026-09-08/09.
- Mislabel-probability likelihood weighting: closed, ~1% effect.
- absolute_fit_pvalue: retired.

**Stop here.** Nothing has been implemented. Awaiting the user's verdict on which
items to build, which to document, and which decisions (F2, F3, F6, F8, F9, the
review bundle, the archive list) to take.

---

## J. Items relayed from the user's parallel session (2026-09-13), for the same verdict

1. **`sampling_group` should become an exported, tested TaxaExpect function.** The
   inline `case_when()` has drifted in three separate incidents (Phaeophyceae and
   Dinophyceae 2026-09-06; five more classes found today). Ship with (a) a kingdom
   guard as default (a catch-all row whose kingdom is not Animalia/Metazoa cannot
   be a macroinvertebrate), which closes the open-ended protist tail without
   re-enumerating classes; (b) the backbone-harmonisation idiom
   `verify_taxon_names(backbone_id = 11)` -> `change_backbone()` -> classify,
   without which an NCBI-backbone match object flips the scope verdict for 139 of
   11,326 ESVs (834 before that session's patches). That session's
   `scope_classifier.R` is a prototype with a frozen baseline reproducing the
   shipped workflow exactly (1,375,405/1,375,405). Pairs with F5 here: the column
   also never reaches the consensus table, so the package function is the vehicle
   for both fixes.
2. **PtCon 18S has a live `sampling_group` bug now**, measured on its saved
   `occurrences_clean`: 2,773 diatom records (Bacillariophyceae) filed as
   macroinvertebrates, plus 66 copepods missed because the zooplankton clause names
   Hexanauplia while live GBIF returns class Copepoda. Negligible for
   macroinvertebrates (2,773 of 1.27 M) but material for phytoplankton, whose
   stratum goes from 1,203 to ~3,982 records, a 3.3x change in that group's
   dark-diversity floor (1/(N+1) on the group's own count). Trap: GBIF puts diatoms
   in the same phylum (Ochrophyta) as the kelps, so the rule must be class-level.
   (2026-09-13, later: fixed via `TaxaTools::assign_sampling_group()`, now wired
   into the 18S workflow -- also adds a 114,744-record Liliopsida correction found
   the same day. Every per-group number above is from the pre-fix run and is
   stale until 18S is re-run.)
3. **A bimodal-H1 diagnostic.** `train_likelihood_model()` and
   `calibrate_query_noise(offset_form = "linear")` assume a unimodal H1 score
   distribution. A Nanopore top-hit distribution measured today has a 20.3% spike
   at exactly 100 and a tail reaching 94.1 at the 10th percentile, against a tight
   unimodal Illumina distribution for the same marker. A warning in
   `calibrate_query_noise()` or `evaluate_likelihoods()` when the H1 distribution is
   detectably bimodal would catch this silently-wrong case.
4. Two roxygen lines (done today in the easy batch): `update_prior_from_consensus()`
   `spatial_group_map` is binary membership with no distance decay;
   `estimate_kernel_priors(covariate_col=)` takes a single scalar.
5. Incidental: `best_hit_pident` is NA for 80% of rows in the 18S match object; it
   is populated by the reference-screen machinery, not universally.

## K. Status after the easy batch (2026-09-13, later)

All edits below are uncommitted in the working tree. `devtools::document()` was run on 7
packages; `devtools::check()` is running separately and its result is NOT known to this
session -- treat as devtools::check() 0 errors / 0 warnings on all 8 touched packages (4 top-level-file NOTEs, all from README.md.bak_* files, now .Rbuildignored in every package); all 9 packages reinstalled 2026-09-13 18:14 UTC to ~/Library/R/4.0/library, not passed or failed. Nothing has been reinstalled yet.

**DONE:**
- A1 FAST multi-site workflow: added the missing `.not_clamp` downranking exclusion.
- A2 TaxaWizard `.extract_param_docs()`: reads `doc$inputs` (was `doc$params` only --
  every generated param block read "(no params)"), + regression test.
- A5 TaxaExpect `generate_domestic_food_priors()`: `.norm_kingdom()` returns NA for
  Eukaryota/Bacteria/Archaea so a superkingdom is never compared as a kingdom.
- A6 TaxaTools `scientific_to_common()`: `llm_parsed` is now per row (an LLM-omitted name
  is no longer cached as "no common name"), + regression test.
- A7 `W_CLAMP <- W_SCALE * exp(-D_CAP / D_HALF)` derived (was a literal) in GL, PtCon 12S
  single, and Mugu workflows.
- A9 Mugu `RERUN_FROM_STEP <- Inf` (step 3 had invalidated every checkpoint at step >= 3 on
  every run since 2026-08-29).
- A11 `^archive_glmm_prior_pipeline$` added to TaxaExpect/.Rbuildignore.
- A12 `misc review docs/code.json` replaced with root's (was MIT).
- A13 all 9 `inst/CITATION` -> version 0.1.0 + github.com/DOI-USGS/TaxaID; root README
  install/issues links likewise.
- A14 TaxaFetch `get_keys_from_context()` uses `[[ ]]` (usageKey/rank warnings gone).
- A15 TaxaLikely `train_likelihood_model()` dead singleton self-match branch + its
  every-run warning removed.
- Docs: NEWS.md created for TaxaFlag and TaxaWizard; post-09-05 entries added to
  TaxaAssign/TaxaExpect/TaxaMatch/TaxaLikely NEWS; NAME_CHANGE_HISTORY gained the six
  09-12/13 changes; LICENSE.md + CLAUDE.md glmmTMB caveat replaced; INTRO.md "four" ->
  "nine" packages; TaxaWizard metadata phantom `reference_errors` removed,
  `standardize_match_data` `data` made optional, two prompt falsehoods (grid/Moran text)
  rewritten.
- Roxygen: posterior_consensus, update_prior_from_consensus, estimate_kernel_priors,
  train_likelihood_model, evaluate_likelihoods, calibrate_query_noise, score_consensus,
  download_gbif_occurrences, verify_removal_candidates, scientific_to_common,
  save/apply_spatial_review_decisions (detail in each package's own CLAUDE.md).
- READMEs: 19 fixes (examples that errored as written in root/TaxaFetch/TaxaMatch;
  counts; azure provider; iNat row; session narrative stripped).
- Two new regression tests (TaxaWizard test-graph.R; TaxaTools common_names).
- Test counts: TaxaTools 933/0, TaxaFetch 781/2 (pre-existing CoordinateCleaner env
  failures), TaxaExpect 639/0, TaxaLikely 1099/0, TaxaWizard 637/0.
- `devtools::document()` run on 7 packages.

**AWAITING USER VERDICT (not implemented):**
- A3 group-prior branch filter (TaxaAssign `group_priors.R:143-148`)
- A4 pending-key clearing (TaxaFetch `download_gbif_occurrences.R`)
- A8 GL cache gates
- A10/F2 retire the stale multi-site file
- B1 multi-site mixture guard
- C2/C3 downranking scope (TaxaAssign)
- D-A1 spatial-review seeding (TaxaHabitat)
- E1 TaxaWizard snippets (cached habitat, evidence block, species_reference)
- G-C2 tile-check cache
- vignettes, pkgdown
- Section J (sampling_group package function, 18S sampling_group bug, bimodal-H1
  diagnostic) from the user's parallel session

The workflow-repo edits referenced above (FAST, GL, S, U) are uncommitted in
`~/My Drive/Rscripts/eDNA` and `~/My Drive/Stats and Data/GreatLakes data` -- neither is
part of this package repo.

---

## L. Implementation record (2026-09-13, evening) -- user went through Sections A-K item by item

Every item below was decided by the user in sequence, then built, tested and
installed the same session. `devtools::check()` 0 errors / 0 warnings on all
nine packages; all nine reinstalled; the eight pkgdown sites rebuilt.

| # | Item | Decision and outcome |
|---|---|---|
| A3 | Group-scope plausibility branch-blind | `compute_group_priors(allowed_branches = c("resident_observed","transport"))`. MEASURED first on PtCon 12S run 2: of 264 winner-scope `unprecedented` rows, 263 read non-unprecedented at consensus scope and only 2 had genuine group backing; 181 of the rest were domestic/transport rows (kept) and 75 rested on nothing but a clamp or evidence row (now excluded). The skepticism gate had never seen a neon tetra, a plains minnow or a red deer at a marine site. |
| A4 | Pending GBIF key loops forever | Dead key is cleared and a fresh request submitted in the SAME call; new `pending_max_age_days = 30` abandons a stale key without polling. `.gbif_wait_with_retry()` returns a classed `gbif_poll_dead` failure instead of `stop()`ing; the fresh-submit caller still errors, the pending caller recovers. Transient behaviour byte-identical. |
| A8 | GreatLakes had no cache gates | `.cache_ok()` ported from the single-site file; `raw_gbif` gated on its checkpoint AND `inputs = bbox_cache` (so a `REDRAW_BBOX` run invalidates it); saved only on a fresh fetch; `overwrite = TRUE` dropped; outlier check gated on `inputs = raw_gbif_path`. |
| F2 | Stale full multi-site workflow | RETIRED to `PtConception/_archive_retired_scripts_2026_09_13/` with a README (git mv), its two July checkpoints alongside. SIX production workflows remain. `FAST_SUBSET <- FALSE` is the full-data path. |
| B1 | Multi-site mixture inherited from first site | `combine_multisite_priors()` now blanks `prior_mix_*` on a combined row whose sites DISAGREE and warns naming the candidates, so `compute_posterior()` samples the recombined Beta instead of one site's Bernoulli. Identical rows (today's only case) are inherited unchanged. |
| C2/C3 | Downranking scope | BOTH. Package: new `posterior_consensus(downrank_requires_candidate = TRUE)` -- a narrowing must land at or above a taxon the observation actually scored. It is a TAXONOMY test, not a string match, so family -> genus *Ulva* is kept when the candidates are *Ulva* species while genus -> *U. lactuca* is blocked. Workflows: the species reference is now built from `prior_branch %in% c("resident_observed","transport")`, not the clamp source string (6 files). MEASURED before the gate: 35 of 150 downranked rows across four sites named a taxon outside their own candidate set -- PtCon 18S *Ulva lactuca* x21, PtCon 12S *Sardinops sagax* and an *Oncorhynchus* genus call whose only candidates were *Salmo* and *Salvelinus*, Mugu *Pseudotolithus senegallus*. Not 1 of 145. Corroboration: `add_slash_taxon()` already carried a downstream guard for this exact shape. |
| D-A1 | Spatial-review seeding | MEASURED: all three seeded decision files are clean -- 0 rows with `habitat_reassigned = TRUE` out of 244,860, 0 frozen habitats, and all four live call sites pass `before =`. The worry was unfounded. Added only the guard: `save_spatial_review_decisions()` now warns, naming the count, when `before = NULL` would record habitats as reassignments. |
| E1 | TaxaWizard | FULL option. Three Tier-1 snippets fixed (cached `build_habitat_lookup()`; `species_reference` + `add_slash_taxon()`; `review_assignments(cache_dir=)`); the curve-pricing EVIDENCE BLOCK ported behind `{{include_evidence_block}}` with `W_CLAMP` derived; graph edges updated; metadata 71 -> 94 entries across 7 files; a structural guard test now asserts every function named in a snippet or edge is a real export (found 0 offenders). 639 tests. |
| G-C2 | Uncached GBIF tile check | `check_gbif_tile_range(cache_dir=)`, one file per (taxon key, rounded lat/lon, buffer, zoom, escalate, min_zoom, base_url), full key verified on read, NO expiry by user decision, `attr(, "cache_age_days")` reported. `generate_regional_proximity_evidence(tile_cache_dir=)` prints one line: N from cache (oldest X days), M fetched. Wired into GL, PtCon 12S, Mugu. No year dimension: GBIF density tiles are not year-filterable, which is why Stage 2 exists. |
| -- | Vignettes | Static guard in all 8 packages with vignettes: every `Pkg::fn()` call and named argument in every chunk (evaluated or not) must be real. FOUND AND FIXED one real defect -- `TaxaAssign/vignettes/taxaid-ecosystem.Rmd` passed a third argument to `expand_unreferenced_hypotheses()`, stranded by the 2026-07-10 package move. Six mostly-unevaluated vignettes gained a sentence saying chunks are illustrative and why. |
| -- | pkgdown | All 8 sites rebuilt 2026-09-13 20:17-20:19 against current code. No `_pkgdown.yml` added; hosting is still undecided (the builder's own note), so grouping and URL wait for that. |
| J1 | `sampling_group` as a package function | `TaxaTools::assign_sampling_group()` + `default_sampling_scheme()` -- an ORDERED, first-match-wins rule list (overridable per assay via `scheme =`), a kingdom guard returning NA rather than the catch-all for a non-animal row, and optional backbone harmonisation (off by default; one lookup per unique name). Regression against the full 2,185,193-row 18S checkpoint: reproduces the inline classifier exactly apart from the intended corrections, 0 unexplained differences. |
| J1a | FOURTH drift instance, found BY the new guard | `Liliopsida` (monocots) was absent from the vascular-plant clause: 114,744 records, 5.25% of the PtCon pool, had been falling into `macroinvertebrates`. Second-largest miscount in this scheme's history after the 484,072 fish. It read as covered because the seagrass rule catches the monocot order Alismatales. VERIFIED LIVE against GBIF: *Zostera marina*, *Phyllospadix torreyi*, *Posidonia oceanica* all carry class `Liliopsida` AND order `Alismatales`, so first-match-wins is load-bearing and adding the class cannot steal a seagrass; the leftover records are Poales/Arecales land plants. ALSO: the clause's `"Zygnemophyceae"` matches NOTHING in GBIF's backbone -- a dead entry since it was written; GBIF's accepted class is `"Zygnematophyceae"` (7 records). Both corrected. After the fix: 0 ungrouped rows in 2,185,193. |
| J2 | Rollout | Wired into the 18S workflow (97 lines of inline classifier -> one call; the `.n_fishes` regression guard kept) and the template's commented example. NOT wired into PtCon 12S or GreatLakes: verified they have NO classifier at all (only a defensive `any_of("sampling_group")` selector) and their occurrence checkpoints carry no `kingdom`/`phylum`/`class` columns. NOT wired into CaliforniaIntertidal: it calls its own deliberately divergent `classify_sampling_group()` (extra `protists`/`unclassified_non_animal` groups; `macroinvertebrates` in-scope rather than a catch-all), and swapping it would silently collapse those distinctions. The classifier was duplicated in TWO live files plus a commented template example, not five. 18S numbers are labelled stale in both docs until it is re-run. |
| J3 | Bimodal-H1 diagnostic | Two-component normal mixture by a deterministic base-R EM, compared to one by BIC, warning in `calibrate_query_noise()`, evidence recorded in `train_likelihood_model()`'s `Stats$h1_bimodality`. No new dependency. A `delta_bic > 10` + mean-separation rule ALONE false-positived on the ceiling-skewed unimodal fixture -- the exact failure that ruled out the bimodality coefficient -- so a third condition requires a genuine density valley between the fitted means. The 10 threshold was checked against Kass & Raftery (1995) JASA 90(430):773-795 directly. Diagnostic only: the remedy for genuinely mixed platforms is to calibrate them separately, which the package does not do for you. |

### Not done, deliberately
- 18S has NOT been re-run; its per-group numbers everywhere are pre-fix and labelled so.
- No `_pkgdown.yml`, pending the hosting decision.
- CaliforniaIntertidal keeps its own classifier; converging it onto a `scheme =` object is a decision for that project, with its own before/after comparison.
- Per-platform likelihood calibration (the real remedy behind J3) is not designed.
- Nothing committed in any of the three repositories.

---

## M. Fast-workflow validation, and a correction to A3 (2026-09-13, late)

The four existing smoke tests were re-run first: all pass, PtCon 18S reproduces
`irreducible_consensus` 82 FALSE / 112 TRUE exactly as on 2026-09-07, and Mugu
still resolves *Fundulus parvipinnis* at 0.999. Those fixtures predate today's
work, so they prove nothing BROKE -- not that the new code works.

NEW `diagnostics/fast_workflows/run_review_fixes_fast_check.R` exercises the
changes themselves, in before/after arms, on real fixtures. ~46 s.

**It immediately caught a real over-reach in A3, which has been corrected.**
`resident_undetected` is not one population. At PtCon 12S it splits:

| Sub-population | Rows | `taxon_name` | What it is |
|---|---|---|---|
| `evidence_blend` with an `evidence_sources` value | 258 | named | a named foreign species elevated by a clamp, regional record, watch list or iNat range |
| `singleton_mirror`/`global_floor`, no evidence source | 37 | NA, keyed by genus | Good-Turing dark-diversity mass, derived FROM that group's own local records |

The first version of the fix filtered on `prior_branch`, which discarded BOTH.
Only the first is spurious: a singleton mirror exists precisely BECAUSE the
group has local records. At PtCon 18S the resident rows carry no genus/family
at all, so those anonymous mirrors are the DOMINANT source of genus- and
family-level group mass -- filtering by branch would have removed it.

Corrected: `compute_group_priors(exclude_named_evidence = TRUE)`, keyed on
`evidence_sources`, not on `prior_branch`. Measured on the real 12S priors
(783 rows): 258 named-evidence rows excluded, 37 mirrors kept; group rows
genus 161 -> 43, family 66 -> 30, species 744 -> 486; 412 groups lose support
entirely and the examples are exactly right -- *Abudefduf hoefleri*,
*Acanthopsetta nadeshnyi*, *Anas poecilorhyncha*, *Arabitragus jayakari* (a
Middle Eastern tahr). The six workflow comments naming the old argument were
updated; no workflow ever passed it. TaxaAssign 789 tests, check 0/0/0.

**Arm results.** A: real 12S as above; a no-op on the 18S fixture, correctly,
since that table predates curve pricing and has no `evidence_sources` column.
C: the mismatched-mixture warning fires, the columns blank, alpha/beta stay
finite, the identical-mixture control passes through untouched (semi-synthetic,
labelled as such). D: 0 ungrouped of 2,185,193.

**Two honest nulls, worth recording so they are not mistaken for coverage.**
B: the 18S fixture's 238 `resident_undetected` rows are all anonymous
(`taxon_name` NA), so they were never eligible as a `species_reference` row
under either construction -- OLD and NEW are byte-identical there, only 1
downranking occurs in 194 observations and it is already legitimate. The
downranking gate is covered by unit tests and by the 35-of-150 production
measurement, NOT by this fixture. E: `calibrate_query_noise()` needs >= 30
confident observations and the 18S fixture yields 1, so the bimodality check
never executes; GreatLakes and PtCon 12S have no priors fixture in that
directory at all. **A fixture that can exercise B and E is the obvious next
addition to that directory.**

Also added: a standing test that every TaxaWizard snippet still PARSES once its
placeholders are substituted (30 snippets, 0 failures). The existing guard
proves the functions named in a snippet are real; it does not prove the
template emits valid R, which is what a user actually runs -- and the new
evidence block is the largest snippet in the set at 17 placeholders.
