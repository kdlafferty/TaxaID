# Pre-publication screen for TaxaID 1.0

**Status: OPEN. Rewritten 2026-09-20 (Fable 5.1, with the user) to replace the
2026-09-14 version, which was written but never run -- its author session crashed
around 2026-09-15.** The old version's running order, closed-item narratives and
pkgdown contradiction are gone; git has them. Everything below was measured on
2026-09-20 against `main` at `162de62` unless a line says otherwise.

---

## 1. Purpose and governing principle

Every pre-publication pass so far has *added*: a fix, a function, a doc, a
re-entry prompt. Each addition widened the surface the next pass had to check,
which found more, which added more. That loop is why the ecosystem is hard to
finish, review and use. This screen is the first pass allowed to **subtract**,
and it succeeds by *finding nothing material* at the end, not by finding things.

Two consequences shape everything here:

- **From a user's perspective, what ships is TaxaID 1.0.** A 1.0 has no
  predecessor. Nothing user-facing says what a function used to do, when a
  default changed, or which session changed it. Rationale stays ("we chose
  kernels over grids because ..."); history goes.
- **The screen is verification plus subtraction, under a growth freeze.** The
  freeze is a *guide*, not a hard rule: the user prefers splitting to catch-all
  functions, and running real data through the package has been the best way
  to improve it, so some additions during the screen are expected. Each one is
  discussed, ledgered (section 5) and reviewed -- never silent.

## 2. Related documents (read before starting a pass)

| document | role in the screen |
|---|---|
| `REVIEW_PROMPT_full_ecosystem_review_2026_09_13.md` + `fable_ecosystem_review_2026-09-13.md` | the last *discovery* review; this screen is its closing counterpart, not a repeat |
| Claude memory `pre-code-review-package-checklist` (9 passes: debris, non-ASCII, names, doc completeness, lintr, check+test, vulnerabilities/domain, CLAUDE.md, commit) | the **per-package** layer; Stage B runs passes 1-7 per package |
| `inst/Code and Domain Review 2.Rmd` | Micah Wright's review template; applied to post-review functions in A5 |
| `inst/extra_functions_for_review.md` | the 2026-08-11 method for "functions written after the review", with per-package review-pulled dates; regenerated at the freeze tag in A5 |
| `usgs_release_review/README.md` | the WERC *release* review (distinct from Micah's code review); three items undecided, no written response exists |
| `CACHE_POLICY_REVIEW_2026_09_14.md` | the one cache policy; A6 documents it for users, does not reopen it |
| `REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` | run checklist for B2, not a work order |

## 3. Decisions taken (user, 2026-09-20)

1. **Growth freeze as a guide.** No new exports on `main` without discussion;
   splitting an overgrown function is a legitimate addition.
2. **Freeze mechanics:** a tag, a git-derived ledger, the workflow chat on a
   branch, a tracker chat that keeps the review responses current (section 5).
3. **`*_clear_cache()` x6:** API left alone, pattern documented once
   (assumption from "cache may do work in other projects"; revisit if wrong).
4. **Legacy tolerances are deleted from the repo.** No pre-1.0 string, key or
   file format is recognised by 1.0 code.
5. **Caches:** never in the repo; disk footprint matters. The reference
   mislabel-detection cache (TaxaMatch/TaxaLikely verdicts) is worth keeping
   across projects; the GBIF cache is disposable.
6. **`CLAUDE.md` history stays** (it is agent context, `.Rbuildignore`d, and
   has been useful). **Public-facing surfaces are fixed**: README, roxygen,
   vignettes, NEWS, `ecosystem_docs/`.
7. **`ecosystem_docs/` and `NEWS.md` collapse** to 1.0-appropriate content.
8. **Change-log stamps leave user view** entirely.
9. **Empirical workflows and site analyses leave the TaxaID repo.** The user
   judges this separation to have been done poorly so far.
10. **Multiple chats continue**, partitioned by repository/package, with
    "check the thing" as the tie-breaker when they disagree.

## 4. State on 2026-09-20 (the numbers the passes start from)

- 9 packages, **225 exports**, **101,089 lines** in `R/`, **59,000 lines** of
  tests (7,394 tests green on 2026-09-15).
- **At least 52 exports postdate the per-package review dates**
  (2026-06-27 to 2026-08-09; count uses 2026-08-11 as a floor). Six are
  per-package `*_clear_cache()`.
- Roxygen (user-facing help) carries **295 date stamps, 53 "Session N",
  28 "previously", 26 "no longer", 21 "renamed", 16 "superseded",
  13 "legacy", 12 "retired"**. TaxaMatch 132 hits, TaxaLikely 107.
- Legacy-tolerance *code* (not prose): ~16 grep hits, TaxaLikely 9,
  TaxaAssign 3 (incl. `.KERNEL_BRANCH <- c("kernel_estimated",
  "resident_observed")`), TaxaMatch 2, TaxaExpect 1, TaxaWizard 1; plus
  `TaxaMatch::migrate_reference_cache()`, whose only purpose is pre-1.0 caches.
- `CLAUDE.md` files total **2.1 MB** (root 529 KB, 3,672 lines; TaxaLikely
  422 KB). All `.Rbuildignore`d; all in the public repo.
- Signal neutrality: root README balanced (sequence 36 / image 20 /
  acoustic 17 / eDNA 16). Leaks: TaxaLikely README eDNA x8, TaxaFlag README
  ESV x6.
- Caches: none tracked in the repo. On disk `~/Library/Caches/org.R-project.R/R/`:
  TaxaFetch **2.7 GB**, TaxaLikely 109 MB, TaxaTools 4 KB, TaxaWizard 216 KB;
  TaxaMatch absent (workflows pass explicit `cache_dir`s).
- Empirical/site material inside TaxaID: `diagnostics/` (45 tracked files,
  most site-named), untracked `GL_presentation/` 27 MB,
  `TaxaID_presentation_files/` 6.5 MB, `presentation_analyses/`,
  `taxaid_burns_harbor_app/`, `Claude outputs/`,
  `archive_retired_workflow_template_2026_09_15/`; per-package
  `archive_*` dirs in TaxaLikely (4) and TaxaExpect (1, the GLMM pipeline);
  `TaxaMatch/inst/extdata` is 60 MB.
- Residue: **17 `.bak` files** in TaxaID (2026-09-12..19) and 7 in the two
  workflow repos, all postdating the convention's retirement on 2026-09-13;
  one stash (2026-09-18, `p1b-rd-parse`, llm_prompts regeneration);
  **21 merged branches** undeleted; root strays `KPCO*.csv`,
  `PtCon18SSchulte_*.rds`, `Rplots.pdf`, `README.html(+.bak)`. No git lock,
  merge or rebase state; no untracked files; worktree list clean.
- **Concurrency, live:** a second session is editing `TaxaFlag`,
  `TaxaHabitat` and `eDNA/PtConception/Multi_site_multi_marker/` on `main`
  (7 uncommitted TaxaID files, 2 in eDNA). `CaliforniaIntertidalWorkflow_
  multi_marker.R` has 23 `## STUB`s. This is the "large workflow" of
  section 5; it will run for days.

## 5. Freeze protocol (the cake-and-eat-it mechanism)

The workflow work does not stop, and the screen does not wait for it.

1. **Tag.** When Stage A is done and the user declares the freeze:
   `git tag pre-1.0-freeze` on `main` in TaxaID. Stage B runs against the tag.
2. **The ledger is git, not self-report.** What changed since the freeze is
   `git log pre-1.0-freeze..main --name-status -- '*/R/' '*/NAMESPACE' '*/tests/'`.
   Nobody is asked to remember to announce a function; the query finds it.
3. **The workflow chat works on a branch** (`workflow-<site>`), commits as it
   goes, and merges to `main` only via the tracker. Package fixes it needs are
   committed on the branch with a test.
4. **The tracker chat** (a separate, cheap-model chat the user runs) does three
   things at each checkpoint and nothing else: runs the ledger query; for every
   new or changed exported function, checks a test exists and adds/updates the
   line in that package's `inst/*_review_response.md` "Added after the review"
   section (name, one-line purpose, test file -- no narration); flags to the
   user anything that is a new export, so the freeze-as-guide discussion
   happens. It does not review code; A5/B do.
5. **Every post-tag package change re-runs Stage B for that package only**
   (checklist passes 5-7, tests, check). The final named-commit statement
   cites the last such re-run.
6. **Communication channel to other chats:** a 10-line "Release freeze
   protocol" block at the top of root `CLAUDE.md` pointing here, plus a Claude
   memory entry. Both are the only files every chat reads.

## 6. Stage A -- editorial passes (run now; tolerate a moving tree)

Each pass is per-file and disjoint from the live workflow edits. Discovery on
Sonnet, adjudication on the expensive model, user decides anything marked
*decide*. "Done when" is the check, not the proxy.

### A1. Metadiscourse purge (roxygen, README, vignettes, NEWS)

Three kinds, three treatments:
- **Rationale** (`@section Why the query is the primer-stripped amplicon
  (2026-09-03)`) -- keep the reasoning, delete the date and session.
- **Change-log stamps** ("Default changed (Session 151)", "pre-2026-09-02
  behaviour", "previously computed as ...", "no longer ...") -- delete. Where
  the sentence carries a fact a user still needs, restate it in the present
  tense.
- **Grid/GLMM-style history** in READMEs (root 3 hits, TaxaExpect 6) -- one
  sentence of considered-alternatives-and-why, no chronology.
`NEWS.md` x9 -> a single `1.0.0` entry each. Agent: one Sonnet per package,
edits on a branch, `devtools::document()` after.
Three rules added after the first two packages (TaxaMatch 132 -> 21,
TaxaLikely 107 -> 18 roxygen hits):
- **The literal grep undercounts.** History also reads "widened from an
  earlier default", "restore the old implicit behavior", "the original
  implementation", "before this fix", "now uses". Sweep for these and read
  every `@section`/`@details`.
- **No pointers out of the package.** Help text referenced `CLAUDE.md`
  (29 lines), `ecosystem_docs/` (49), `diagnostics/`, `REENTRY_PROMPT_*`,
  `SPEC_*` and `[[memory]]` names -- none exist in an installed package.
  Delete or restate.
- **Runtime strings are user view.** `message()`/`warning()`/`stop()`
  literals carried "pre-Session-139", "pre-2026-09-02", "added Session 158"
  (found with the R parser's `STR_CONST` tokens, since multi-line `paste0()`
  defeats grep). Wording-only edits to these are in scope. **Done when** the grep of
section 4 returns 0 for session/date/previously/no-longer/renamed/superseded/
legacy/retired in `R/*.R` roxygen, READMEs and vignettes, *and* a reader
opening five random help pages finds the reasoning intact.

### A2. Legacy-tolerance deletion (code)

Delete every code path that recognises a pre-1.0 string, key or file layout
(section 4 list), and `migrate_reference_cache()` (*decide*: it is the one
function whose deletion could strand the user's own mislabel cache -- run it
once on that cache first, then delete). Tests that exercise the tolerance are
deleted with it; tests asserting the *new* behaviour stay. **Done when** the
grep is 0 and every package's tests pass.
**Targets surfaced by A1 (2026-09-20), code + roxygen together:**
- TaxaAssign `kernel_branch.R`: `.KERNEL_BRANCH <- c("kernel_estimated",
  "resident_observed")` -> one label (A1 had rewritten the roxygen to say both
  are "permanently accepted"; decision 4 says otherwise).
- TaxaAssign `posterior_consensus.R` (~371, 391, 884): the "legacy GLMM
  tables" / "table predates the kernel schema" fallback reading.
- TaxaAssign `suggest_unreferenced_species()`: a "deprecated forwarding
  wrapper" to TaxaLikely; nothing to forward from in 1.0. Un-export/delete.
- TaxaLikely `fetch.R`: the `"legacy"` cache-generation status and `n_legacy`
  attribute (a tolerance for pre-versioned cache files).
- TaxaMatch `migrate_reference_cache()`: FIRST the user runs, once, on the
  live reference-evaluation cache directory (path still needed):
  `TaxaMatch::migrate_reference_cache("<cache_dir>")` -- success prints the
  carried-forward / left-under-old-key / already-current counts and writes
  `reference_accession_cache.rds.bak_pre_<version>` beside the cache. THEN
  delete: `R/migrate_reference_cache.R`, `man/migrate_reference_cache.Rd`
  (roxygen does not remove orphaned Rd), the `.old_key_cache()` fixture and
  four tests at the end of `tests/testthat/test-local-corroboration.R`, and
  rewrite ~6 roxygen passages in `evaluate_reference_accessions.R` that
  instruct the reader to run it (~41-52, ~142, ~1513, ~1979, ~2005); then
  `devtools::document()`. All other A2 TaxaMatch work is DONE (branch
  `screen-a2-TaxaMatch`, 544 tests green).
- TaxaExpect `estimate_kernel_priors()` / `generate_undetected_diversity()`:
  the `inherits(model_obj, "biofreq_model")` branches and doc references to
  `train_biodiversity_model()`, a function that exists nowhere in the repo --
  the archived GLMM pipeline's input type.
- TaxaWizard: the unused internal "Legacy System Prompt" assembler
  (`engine.R` ~457) and the `metadata` -> `registry` argument alias with its
  deprecation warning -- tolerances for the pre-restructure API.
- **Caches are the exception to "loud failure"**: an unversioned or legacy
  cache entry is a cache MISS (refetch, with a message), not an error; the
  loud `stop()` rule is for data tables (priors, consensus) whose silent loss
  changes results.
- **Consequence of the TaxaLikely cache rule (measured 2026-09-20, read-only):**
  1,932 of 1,933 meta files in `~/Library/Caches/org.R-project.R/R/TaxaLikely`
  lack `sel_params` and all 1,933 lack `acc_version`, so the next production
  fetch treats the whole 109 MB / 25,945-file store as COLD and re-downloads
  from NCBI (hours, not minutes; NCBI throttling applies). Entries self-heal
  on refetch. Schedule that cold run deliberately, before Stage B2, with NCBI
  healthy -- it is needed for B2 anyway.
- **DESCRIPTION files**: A1 excluded them for safety, but TaxaExpect's
  `Description:` still described the retired grid design and rendered in
  `?TaxaExpect` (fixed on its branch). Check all nine `Title:`/`Description:`
  fields before the tag; `Version:` bumps to 1.0.0 at the tag.
- **Stage B check() items found by A1**: TaxaHabitat roxygen has literal
  `[0, 1]`/`[0, 1.05]` ranges parsed as markdown links (report_habitat.R:140,
  151) and a `[.candidate_habitats()]` link (utils_plot.R:541); em-dashes are
  pervasive in TaxaTools and present in TaxaHabitat/TaxaAssign R files
  (checklist pass 2, non-ASCII).

### A3. Signal-neutrality audit

Classify all 225 exports as *signal-specific* (BLAST, amplicon, ESV readers,
BirdNET/image readers) or *generic*. For the generic set, check roxygen prose,
argument names, README paragraphs and -- the usual leak -- `@examples` use
observation/detection vocabulary and are not all DNA. Do not scrub the
signal-specific set. *Decide* borderline names the agent lists (e.g.
`validate_controls()`). **Decided 2026-09-20 for TaxaFlag** (all 12 exports
generic, 16 vocabulary leaks, 3 API-level leaks): `reads_col` ->
`count_col` (default `"count"`) in `flag_contaminant()`,
`validate_controls()`, `build_review_covariates()`; `taxon_col` default
`"ESVId"` -> `"taxon_id"`; `review_assignments(data_type=)` loses its
`"eDNA"` default. Workflow call sites in all three repos change in the same
commit. **A3 audit COMPLETE for all nine packages (2026-09-20;
`scratchpad/A3_partial_reports.md` + `A3_signal_neutrality_remaining.md`):
of 215 exports after A7, 171 generic / 44 signal-specific (32 DNA, 4 image,
1 acoustic, 7 literature). TaxaAssign, TaxaExpect, TaxaHabitat, TaxaWizard
are 100% generic. TaxaFlag's 16 leaks FIXED on its A1 branch. Remaining: 16
prose leaks (Tools 4, Fetch 2, Match 3, Assign 4, Likely 2, Wizard 2) + the
TaxaHabitat README's "Most eDNA studies" line -- apply after merge; two
API-level items and six borderline names need the user (below). Pattern:
generic packages have zero image/acoustic worked examples (TaxaAssign,
TaxaWizard onboarding); TaxaLikely's model functions are neutral but only a
DNA producer (`build_sequence_matrix()`) feeds them.**
**DONE 2026-09-20** by the workflow chat (TaxaID `6870776` on
`workflow-ptcon-multisite`, eDNA `2819a39`, GreatLakes `4218f37`; 618 tests
pass). As built: `count_col` default `"count"` in all three functions; the
`"ESVId"` default existed only in `build_review_covariates()` and became
`"taxon_id"` there; `review_spatial_context()` gained its own required
`data_type` because it forwards to `review_assignments()`. **Output column
names (`n_reads_total`, `min_reads`, `max_reads`, ...) stay as they are** --
production workflows filter on them; renaming outputs is not a docs pass. **Done when** the classification table exists and
every generic export's help page passes a "would an acoustician read this as
theirs?" read.

### A4. Repository hygiene and separation

- **Empirical material out of TaxaID** (decision 9): `diagnostics/` site
  probes, presentations, the Burns Harbor app, `Claude outputs/`, per-package
  `archive_*` dirs. Destination (decided 2026-09-20): a new git repo at
  `~/My Drive/Rscripts/projects/TaxaID_dev/`. `diagnostics/` moves in its
  entirety EXCEPT (decided after the inventory, 2026-09-20)
  `build_workflow_template.R` and the `fast_workflows/` fixtures, which move
  INTO `TaxaWizard/inst/` because the root README's "confirm your
  installation works" section and TaxaWizard's template regression test
  depend on them; both get repointed. The two external `AuditNCBI.R` scripts
  (eDNA/PtConception, GreatLakes data) are repointed to the CSV's new home.
  `.Rproj.user/` (11 GB, root + all nine packages) is DELETED, not moved --
  only after RStudio is closed. The 2026-09-18 stash: inspect, then drop.
  `TaxaHabitat/inst/extdata/ne_10m_minor_islands_coastline.rds` is
  load-bearing but untracked (blanket `*.rds` ignore): force-add it.
  `usgs_release_review/` STAYS (release provenance, B5 runs against it).
- **`ecosystem_docs/` collapse** (decision 7): keep user-facing docs
  (`ECOSYSTEM_WORKFLOW.md`, `EXTERNAL_DATA_SOURCES.md`,
  `STATISTICAL_COMPONENT_CATALOG.md`); move `NAME_CHANGE_HISTORY.md` (it is
  history), `REENTRY_PROMPT_*`, `REVIEW_PROMPT_*`,
  `fable_ecosystem_review_*`, `RECORD_*`, `SPEC_*`, `WORKFLOW_STRUCTURE_
  AUDIT_*` to the dev folder. This document moves last, after Stage B.
- **Residue**: `.bak` x24 (move to `_archive_...`, never `rm` -- Drive
  multi-parent rule), drop the stash after the user confirms it is dead,
  delete the 21 merged branches, move root strays. **Done when** `git branch
  --merged main` lists only `main`, `find -name '*.bak*'` is empty in all
  three repos, and `git status --ignored` at the TaxaID root shows only
  `.Rproj.user`, `pkgdown_sites/` and `.Rhistory`.
- **`TaxaMatch/inst/extdata` 60 MB**: decided -- a 1.0 user needs almost none
  of it. Keep only files referenced by tests, examples or vignettes; the rest
  goes to `TaxaID_dev`.
**EXECUTED 2026-09-20** (branch `screen-a4-moves`, 6 commits; `TaxaID_dev`
created, 338 MB, 10 commits, `PROVENANCE.md`): all of the above plus 19
merged branches deleted, the coastline `.rds` tracked, extdata 60 -> 9.3 MB,
`ecosystem_docs/session_notes/` (found, moved), the template generator and
fast fixtures relocated into `TaxaWizard/inst/` with the test now failing
loudly, both external `AuditNCBI.R` scripts repointed (uncommitted). LEFT FOR
MERGE TIME: untracked residue still inside `diagnostics/` and
`ecosystem_docs/readmes/` in the main checkout (their tracked siblings live
only on the branch until it merges); `.Rproj.user/` (11 GB, RStudio open);
`jv-bracket-consensus` (merged locally, remote-tracking branch stale --
delete with `-D` and `git push origin --delete` at push time); ~25 prose
citations of moved files in CLAUDE.md/dev comments (historical pointers,
left by decision). `llm_prompts/` is touched by three branches and is a
GENERATED artifact: after all merges and a reinstall, regenerate it with
`TaxaWizard::workflow_export_prompts("llm_prompts", overwrite = TRUE,
placeholder_setup_report = TRUE)` rather than merging it by hand.

### A5. Review responses (Micah's code review + the WERC release review)

1. Regenerate `inst/extra_functions_for_review.md`'s catalogue by its own
   method at the current tree (later re-run at the tag): every exported and
   internal function introduced after each package's review-pulled date.
2. Run Micah's template (`inst/Code and Domain Review 2.Rmd`) over exactly
   those functions -- one Sonnet agent per package, adjudicated.
3. Each `inst/*_review_response.md` gains one section, **"Added after the
   review"**: function, one-line purpose, test file. Nothing about how our own
   review changed the code.
4. Strip existing self-review narration from the responses (TaxaHabitat's
   opens with its own 2026-07-28 review-prep pass; others describe
   "reorganised since the review").
5. **WERC release review**: write the response that `usgs_release_review/
   README.md` says does not exist; its three open items are DECIDED
   (user, 2026-09-21): `CLAUDE.md` files stay where they are (agent-context
   for maintainers, `.Rbuildignore`d, never in the built package);
   `ECOSYSTEM_WORKFLOW.md` linked from the root README (already is, line
   ~878); `PACKAGE_SETUP.md` and `DESCRIPTION.md` no longer exist on `main`,
   so the response records them as retired with their content in the root
   README's installation and package sections. Keep the push-back on
   deleting tests, confirmed with the reviewer.
**Done when** every response has the section, none narrates self-review, and
the release-review response exists in that folder.
**FIRST HALF DONE 2026-09-21** (branch `screen-a5-reviews`): catalogue
regenerated at `inst/extra_functions_for_review.md` -- 64 exported / 294
internal functions postdate the human review (TaxaMatch 15, TaxaTools 15,
TaxaExpect 13, TaxaFlag 6, TaxaHabitat 5, TaxaFetch 4, TaxaWizard 4,
TaxaLikely 2, TaxaAssign 0); 29 exports retired since review. All nine
response files carry one "Added after the review" table; self-review
narration removed (-660 lines net). **Template reviews (read-only, one per
package, `scratchpad/A5_review_<Pkg>.md`)**: TaxaMatch done -- 2 DEFECTS,
both reproduced by the coordinator: `flag_incongruent_references()`
multiplies `match_df` rows when `evaluation` holds two version-suffixed
copies of one accession (dedup keys the raw accession before the stripped
join key); `verify_local_corroborations()` can return `status = "clean"`
from a STALE params_key generation because `match()` takes the first
(oldest) cache row. 1 RISK (`.summarise_corroborators()` reads the pair
cache without a params_key filter). Findings are FIXED in code (branch
`screen-a5-fixes`), never narrated in the response files (rule c).
TaxaTools done -- 1 DEFECT, reproduced: the shared cache-clearing engine
(`report_and_clear_cache()`/`list_cache_files()`, used by every package's
`*_clear_cache()`) has no containment check -- `taxatools_clear_cache(
cache_dir = ".")` deletes a pattern-matching user file from the working
directory. Fix in the engine: refuse cwd/home/root, refuse mixed directories
without `force = TRUE`, do not follow symlinks out of `cache_dir`. 2 RISK
(untrusted `readRDS()` of cache/manifest files), 1 DOC ("eleven groups" is
ten names, eleven rules), 1 STYLE (`write_taxaid_manifest()` validates
nothing). Positive: `assign_sampling_group()` and `fetch_worms_attributes()`
are the best-documented, best-tested code reviewed -- every domain rule has a
cited real case and a fixture test reproducing it.
TaxaExpect done -- 1 DEFECT, reproduced: the equirectangular distance
formula (`111 * sqrt(dlat^2 + (dlon * cos(lat))^2)`, naive `lon1 - lon2`)
does not wrap at the antimeridian; a site at 179.9 with records at -179.9
(22 km) got theta 1e-33 while records 2,000 km away got 1.0. The formula is
copy-pasted in FOUR files (`estimate_kernel_priors`, `calibrate_kernel_
bandwidth`, `plot_theta_surface`, `generate_uncertain_habitat_evidence`);
fix = one internal helper with longitude normalisation, all four call it.
No current site is affected. 6 RISK (unvalidated numeric params in
`generate_regional_proximity_evidence()`, a hard-coded 0.05 veto bound, a
comment overclaiming a circularity guard, no Inf guard on `distance_km`),
3 DOC, 2 STYLE. Every checked formula -- Kish n_eff, Beta variance, Chao1,
presence-mixture moments, log-link curve fit, FFT lattice -- matches its
roxygen; `plot_theta_surface()`'s site-identity invariant verified live.
TaxaFlag done -- 2 DEFECTS in `validate_controls()`, reproduced: an all-zero
control column vanishes from the output (no row, no verdict) against its
"one row per sampled unit" contract; the per-column distance loop is
uncapped, 68.8 s at the 1,151-sample case its own roxygen cites. 3 RISK:
the contaminant evidence gate is a count floor, not a significance test
(honestly disclosed in the roxygen -- the open item from the 2026-09-20
design); LLM prompt text is unescaped user data (bounded: nothing executes
on the reply); returned categories not validated against the enum. API
keys never enter TaxaFlag code; cache paths are hashes; the Shiny gadget
has no `eval`/`parse`/`HTML()` sink.
TaxaHabitat done -- 5 DEFECTS, reproduced (branch `screen-a5-fixes-habitat`):
(1) `save_/apply_spatial_review_decisions()` key on `point_id` alone, so two
taxa sharing a point get one taxon's flag applied to both and the other
never resurfaces -- the user's three real decision files (GreatLakes 5,044
rows, PtCon, Mugu) carry NO taxon column; fix keys on `(point_id,
taxon_name)`, applies old-format files only to single-taxon points, and
reports ambiguous points loudly for re-review; (2) re-applying compounds
the reason prefix while `n_applied` says 0; (3) `.utm_crs_for()` picks the
Greenwich UTM zone for points straddling 180 degrees; (4) decision files
are `readRDS()`'d with no schema check; (5) the end-to-end geography test
passes vacuously when resolution returns NA. Confirmed as documented:
coastline/minor-islands/EPSG rule, UPS above 84 degrees, NA coordinates,
on-coastline points, the occurrence-side vs taxon-side Uncertain routing,
the LLM cache key.
**Seven fixes MERGED 2026-09-21 (`dc820c6`)**: TaxaMatch row multiplication
(highest numeric accession version wins, documented) and stale-generation
corroborator verdicts (lookup restricted to the current params_key, newest
`evaluated_at` wins -- CAVEAT: `verify_local_corroborations()` uses the
DEFAULT params key because it receives no BLAST parameters; a run evaluated
under non-default parameters reads every corroborator as "unchecked" --
conservative, but a follow-up should let the caller pass the key or derive
it from the audited run, as `.summarise_corroborators()` already does);
cache-clear containment in the shared engine (refuse cwd/home/root, refuse
mixed directories without `force = TRUE`, never follow symlinks out);
antimeridian-safe `.approx_distance_km()` replacing four inline copies;
template generator declares `data_type`, its diff test fails rather than
skips, and a new test pins every canonical-path placeholder to CONFIG/
DATAFLOW; `validate_controls()` gives all-zero columns an explicit
`no_detections` row and its distance step is vectorised (1,151-sample case
~16.5 s -> 1.3 s end-to-end, bit-identical). Tests: TaxaMatch 1,364,
TaxaTools 1,174, TaxaExpect 701, TaxaFlag 580, all zero failures. One known
gap until the next reinstall: TaxaWizard's committed-template diff test
compares against the installed library, which predates today's inst/ edits.
TaxaFetch done -- 2 DEFECTS, reproduced (branch `screen-a5-fixes-fetch`):
`check_geographic_outliers()` names its verdict cache by `sum(keys) %% 1e9`
-- not a hash; equal-sum key sets collide and the second call silently
marks every record "insufficient_global_data" (fix: `rlang::hash()` of the
sorted keys + verdict parameters, the package's existing convention, and a
guard treating a file with none of the requested ids as a miss);
`dedupe_occurrences()` crashes when a key column is absent while its docs
promise a no-op (fix: loud `stop()` naming the missing columns). 1 RISK:
iNaturalist calls have no retry/backoff on 429/5xx (fix: reuse the GBIF
retry engine). Open question for someone with API access: whether omitting
iNat's `captive`/`quality_grade` params really means "no filter".
**TaxaHabitat fixes MERGED (`9debda7`)**: decisions key on `(point_id,
taxon_name)` -- `point_id` is a coordinate id from `stack_occurrences()`
shared across taxa, so the collision was real; old-format files apply only
to single-taxon points and ambiguous ones return for review with a
warning; apply is idempotent; `.utm_crs_for()` wraps at the antimeridian
(-179.5/179.5 -> zone 60); decision files are schema-validated; the
geography test skips only when NOAA is provably unreachable. 580 tests,
0 failures. **User-facing consequence**: the next real
`apply_spatial_review_decisions()` run on the GreatLakes/PtCon/Mugu files
reports how many points are ambiguous; re-saving from the review gadget
writes the new key.
**TaxaFetch fixes MERGED (`6a0b2da`)**: verdict cache keyed on
`rlang::hash()` of the sorted species keys + `year_range`/`method`/
`min_occs`/`tdi`/`mltpl`, with a read guard treating a file sharing none of
the requested gbifIDs as a miss (note: `literature_search.R` uses its own
`.query_hash()`, so the package now has two hashing conventions -- a
1.1 tidy-up); `dedupe_occurrences()` stops naming missing key columns;
iNaturalist calls retry 429/5xx with bounded backoff honouring
`Retry-After` (new `retry_attempts`/`retry_wait` arguments, mirroring the
GBIF convention). 824 tests, 0 failures. iNat's omitted `captive`/
`quality_grade` = no filter per the API's documented behaviour; not
live-verified.
TaxaWizard done -- 1 DEFECT, reproduced, CONFIDENTIALITY (branch
`screen-a5-fixes-wizard`): the chat engine's auto-sniff
(`.detect_paths_in_text()` -> `.format_sniff_block()`, graph.R ~583) reads
ANY existing local file whose path is mentioned in chat text and injects
its first line into the prompt sent to the LLM provider -- reproduced with
`/etc/hosts` and a synthetic secret; `.rds` mentions are `readRDS()`'d with
no size cap. Fix: data-extension allow-list, working-directory scope,
never dotfiles/system paths, 1 MB cap for rds, summary-only (column names,
never content) into the prompt. 4 RISK incl. `.validate_one_call()`
SKIPPING when a package fails to load (becomes a failure code). Verified
clean: registry argument parsing (27-parameter function spot-checked live),
cache key sufficient for reinstalls, no key value ever in a prompt or
pack, `workflow_export_prompts()` cannot write outside `dir`.
TaxaLikely done (last of eight) -- 2 DEFECTS, reproduced (branch
`screen-a5-fixes-likely`): `suggest_unreferenced_species()` never checks
that `reference_species` is present for acoustic/image data, so omitting it
silently flags every LLM candidate as unreferenced (the non-eDNA branches
had zero tests); its response parsers accept any two-word string under any
genus ("Ignore priorinstructions" passed under Gadus). 1 RISK (genus column
reaches the prompt unvalidated), 1 DOC (`n_cross_genus_pairs` reports
2x the true count). `check_cross_genus_sampling_noise()`'s resampling and
`taxalikely_clear_cache()`'s patterns verified live.
**A5 first half MERGED (`24c6e5e`)**: catalogue at `inst/extra_functions_
for_review.md`; every response file has its "Added after the review" table;
conflicts with A8's pointer fixes resolved toward A5 (the passages were
deleted), two lost pointer fixes re-applied.
**Template-review tally, all eight packages: 16 reproduced defects in
post-review code, every one fixed or being fixed on a branch; plus the
ecosystem-wide cache-clear containment gap and the stalled template
generator.**
**TaxaWizard fixes MERGED (`8853188`)**: auto-sniff requires a data
extension from a single allow-list (csv/tsv/txt/tab/dat, fasta/fa/fna/fas,
rds, json -- xlsx/rdata were never parsed and are no longer detected), no
dot-segment, a location under the working directory or the session
`tempdir()`, or an explicitly quoted path outside system directories;
`.rds` is size-capped (1 MB) before `readRDS()`; only column names and
counts reach the prompt, never a content line. `.validate_one_call()` now
emits `package_unavailable` (a failure) instead of skipping an unloadable
package; `workflow_check()`'s roxygen states exactly what it checks and
where snippet validation actually lives. 1,084 pass; the one failing test
is the committed-template diff against the stale installed library.
**TaxaLikely fixes MERGED (`06c6d02`)**: `suggest_unreferenced_species()`
stops when `reference_species` is missing for acoustic/image (first tests of
those branches); LLM responses keep only species whose genus matches the
genus asked about, and family-level responses echo a `family` field that
must match; the genus column is validated before it reaches the prompt;
`n_cross_genus_pairs` counts unordered pairs; the single-genus case warns.
1,325 tests, 0 failures. **Every A5 fix branch is now in `main`**; the
16-defect tally is closed in code.
**`ECOSYSTEM_WORKFLOW.md` REWRITTEN and merged (`b5e547b`)**: 402 -> 376
lines; the TaxaExpect section now describes the kernel pipeline as the
template runs it; the TaxaAssign site/prior join describes `join_priors(
site=)`; the "Open Design Issues" changelog is gone; all 81 function
mentions verified against NAMESPACEs. The rewrite exposed a root-README
contradiction (line ~772 pointed new users to a template in the separate
`eDNA` repo; line ~797 named this repo's generated template canonical) and
a history narrative in the README's template section -- both fixed on
`main`, with two more dated passages (the Xeno-canto quality-grade helper's
archival; "there is no longer a standalone inst/ script"). The root README
was never inside an A1 package pass; it has now had the same treatment.
**Second reinstall DONE 2026-09-21** (window verified: the peer's 30-second
probe had finished; RStudio's session held no TaxaID package): nine packages
from `83a3029`, exports 217, `llm_prompts/` regenerated (`0cd1b6c`),
**TaxaWizard 1,093 pass / 0 fail / 0 skip** -- the committed-template diff
test passes against a current library. Stage A is COMPLETE except the
`.Rproj.user/` deletion (RStudio still open).
**WERC release-review response WRITTEN 2026-09-21**
(`usgs_release_review/RESPONSE_to_release_review.md`), answering every
request in the review's table with the three user decisions applied and the
test-deletion push-back kept.
**NEW FINDING (A8 follow-up, 2026-09-21): `ecosystem_docs/ECOSYSTEM_WORKFLOW.md`
is a KEPT user-facing document, but its "PRIOR PIPELINE" section still
describes the archived GLMM/grid design under a dated "Archived pathway"
banner (~line 205 on). It must be rewritten to the kernel pipeline
(`estimate_kernel_priors()` -> evidence layers -> `apply_undetected_evidence()`
-> TaxaAssign), banner removed -- an agent task, queued.

### A6. Caching and resources, for users

No new framework. One root-README section, "Caching and resources": where
`cache_dir` points by default (`tools::R_user_dir(<pkg>, "cache")`), which
caches are worth keeping across projects (the reference mislabel-detection
cache) and which are disposable (GBIF), `taxaid_cache_report(warn_gb=)`, the
`*_clear_cache()` pattern stated once, and which functions are memory-heavy
with their approximate cost (`filter_gbif_quality()` ~4 GB per million rows;
chunk). Then verify: every long-running export documents `cache_dir`; the two
known heavy functions chunk internally. **Done when** the section exists and a
Sonnet agent, given only the README, can answer "where is my cache, how big is
it, how do I clear it, what will blow my RAM" for each package.
**DONE 2026-09-20** (branch `screen-a6-caching`, `02c9012`, 74 lines before
"# Troubleshooting"). Verified facts that corrected the brief: TaxaHabitat and
TaxaFlag cache only when `cache_dir` is passed (workflows do); TaxaTools has a
fixed-path model cache, opt-in lookup caches, and a `taxatools_clear_cache()`
with no default; `taxaid_cache_report()` does not scan TaxaWizard;
`filter_gbif_quality()` does NOT chunk (documented as such). Findings routed
to A8: `harvest_dataone_catalog(cache_file = "pasta_catalog.rds")` defaults to
a RELATIVE path in the working directory (the one off-convention cache);
`generate_regional_proximity_evidence()` caches into TaxaFetch's directory
(intended sharing, document it); the Troubleshooting claim that
`blast_sequences()` takes `cache_dir` was false (fixed on the A6 branch).

### A7. Subtraction

- **Zero-caller list**: every export with no caller in TaxaID (outside its own
  package), the two workflow repos, the workflow template, or TaxaWizard's
  registry. User decides per item: keep / internalise / drop. This is the one
  pass that reverses the growth direction; do it before B.
- **Catch-all check**: exports over ~300 lines or with more than ~12 arguments
  listed for the user; splitting is allowed under the freeze-as-guide.
**Done when** the two lists exist with a user decision on each row.
**Result (2026-09-20):** 225 exports, **20 with no external caller**, 39
catch-alls. User decisions: TaxaFetch literature/DataONE screening subsystem
(`build_taxon_screen_prompt`, `parse_taxon_screening_response`,
`parse_geo_screening_response`, `screen_eml_columns`, `fetch_dataone_eml`,
`call_api_pdf`) -> `TaxaID_dev`; `build_review_covariates`,
`fetch_occurrences_by_taxon`, `drop_stale_seeded_decisions`,
`taxalikely_evict_unreachable_cache` -> `TaxaID_dev`;
`identify_confident_observations` -> un-export; TaxaTools model registry
(`list_models`, `refresh_models`, `set_model`, `model_cache_info`),
`fetch_worms_attributes`, `refine_reference_verdicts`,
`verify_local_corroborations`, `correct_training_bias`,
`audit_inat_coverage` -> keep. **No catch-all is split for 1.0**; splitting
is a 1.1 goal. **Execution refinement (2026-09-20):** "zero external caller"
is not "dead" -- four of the TaxaFetch six (`parse_geo_screening_response`,
`screen_eml_columns`, `fetch_dataone_eml`, `call_api_pdf`) are called from
other TaxaFetch files, so they are INTERNALISED (`@export` dropped,
`@keywords internal`), not removed; only `build_taxon_screen_prompt`,
`parse_taxon_screening_response` and `fetch_occurrences_by_taxon` leave the
package. Removed code is staged in the scratchpad `a7_removed/` and lands in
`TaxaID_dev/removed_functions/`. Apply the same internal-caller check before
removing `build_review_covariates`, `drop_stale_seeded_decisions` and
`taxalikely_evict_unreachable_cache`; when the last one goes, delete its
sentence from the A6 README section. The A7 CSV's test-caller column
was wrong (13 of 15 checked have tests); its external-caller column was
verified by opening files.

### A8. Claims-not-code scan

Grep user-facing prose for absolute claims ("never", "always", "cannot",
"guaranteed", "can never again") and check each against the code; the project
has repeatedly shipped comments asserting behaviour the code did not have.
Also reconcile every remaining doc against every other (the old screen
contradicted itself on pkgdown). **Include the manuscript-facing
`inst/*_supplemental_methods.md` files** (TaxaAssign, TaxaExpect, TaxaLikely):
A2 found TaxaExpect's using the retired `resident_observed` label as current
11 times; A1 never covered `inst/`. Also `inst/TaxaExpect_workflow.R`, a
self-labelled "ARCHIVED PATHWAY" script still shipped in `inst/` -> A4 move.
**Done when** each hit is either verified or rewritten.
**SCAN DONE 2026-09-21** (`scratchpad/A8_claims_scan.md`, read-only): ~85
claims opened against code -- 5 FALSE, 4 UNVERIFIABLE (need a live run:
GreatLakes/Lamar validation numbers, log-loss figures), ~76 verified.
FALSE: root README cites `taxalikely_evict_unreachable_cache()` as callable
(removed); TaxaAssign methods file says the forwarding wrapper "remains"
(removed); TaxaLikely methods file presents `identify_confident_observations()`
as public (internal); TaxaExpect methods file calls a 0-of-221 Jeffreys
quantity "about 2.3e-3" an UPPER BOUND -- 2.3e-3 is the posterior MEAN
(0.5/222, recomputed); the 95% upper bound is ~0.9%; root README Software
Inventory stale in 6 of 9 rows. 12 dead file pointers in R/inst/vignettes/
READMEs. 2 of 90 shipped `inst/` scripts call functions that no longer exist
(`TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R` -> 7 archived
GLMM functions; `TaxaExpect/inst/extra_functions_review_inputs.R` -> 2
internals that never existed); 54 of 90 carry dated/session comments -- A1
never covered `inst/`, so an **inst/ sweep** is a Stage A addition. Fixes
apply on the post-merge branch.

### Merge order for the Stage A branches (decided by topology, 2026-09-20)

1. `workflow-ptcon-multisite` (`6870776`: TaxaFlag renames + call sites in
   TaxaWizard snippets, template, README) merges to `main` FIRST.
   `screen-a1-TaxaFlag` was cut from it; the TaxaWizard branches were cut from
   `main` and their `test-validate.R` fails until `6870776` lands.
2. Then, per package, `screen-a1-<pkg>` followed by `screen-a2-<pkg>` (A2
   branches were cut from their A1 branch, so each pair merges as a unit).
3. Then `screen-a6-caching`, then the A4 execution branch (moves), then A5/A8.
4. Every merge: `devtools::document()` diff must be empty and the package's
   `devtools::test()` green in a fresh R process BEFORE any reinstall; reinstall
   only when no other R session has the package loaded.

Follow-up decisions parked from A2: `TaxaWizard/inst/prompts/system_prompt.md`
is now vestigial except its "Pipeline Awareness" section (still read by
`pack.R`) -- trim or leave; `inst/taxawizard_reviewer_demo.R` carries a dated
"deprecated wrappers removed" note (inst/ was outside A1; A4 moves the demo).

### Merge record

**2026-09-21: all Stage A branches merged to `main` at `7b5b6f6`** (user
go-ahead 2026-09-20 night), in the order above; 21 merges, one conflict set
(`screen-a4-moves` vs the A1 branches, both editing the same roxygen pointer
lines -- A1's stricter text kept, `man/` regenerated). Exports 225 -> 218
(DataONE kept whole by user decision; `fetch_occurrences_by_taxon`,
`build_review_covariates`, `drop_stale_seeded_decisions`,
`taxalikely_evict_unreachable_cache`, TaxaAssign's forwarding wrapper gone;
`identify_confident_observations` and `fetch_dataone_eml` internal).
`migrate_reference_cache()` was RUN on all seven live caches first (every
congruent verdict already current; 199 non-congruent rows left to
re-evaluate; `.bak_pre_v5_amplicon_query` beside each) -- its deletion is
now unblocked. Still to do on `main` (on a branch): delete
`migrate_reference_cache()` per the checklist; the A3 follow-ups (remove
`suggest_unreferenced_species(data_type=)`'s default; 16 prose leaks; the
TaxaHabitat README line; image/acoustic examples for the generic layer);
A5; A8. Deferred until no R session holds the packages: reinstall all nine,
regenerate `llm_prompts/`, re-run TaxaWizard's `test-pack`/`test-validate`.
The workflow chat must merge `main` into `workflow-ptcon-multisite` before
further package edits; the untracked residue under `diagnostics/` and
`ecosystem_docs/readmes/` in its checkout moves to `TaxaID_dev` then.

**Verification of the merged tree (2026-09-21, fresh R per package,
`load_all`, no install):** `document()` a no-op in all nine; tests green in
eight -- TaxaTools 1,155, TaxaFetch 790, TaxaMatch 1,387, TaxaLikely 1,283,
TaxaAssign 811, TaxaExpect 693, TaxaHabitat 545, TaxaFlag 550, zero failures.
TaxaWizard 1,067 pass / 4 fail, both failing tests compare against the
INSTALLED libraries (`test-pack`: generated pack vs committed `llm_prompts/`;
`test-workflow-template`: committed template vs the generator's output) and
five installed packages are stale relative to source (TaxaFetch 32 vs 30
exports, TaxaLikely 33/31, TaxaAssign 16/15, TaxaHabitat 19/18, TaxaFlag
12/11). Re-run both after the reinstall; they are not evidence against the
merge until then.

**Reinstall DONE 2026-09-21 07:57** (window verified clear: RStudio's R
session held no TaxaID package; no other R process). All nine installed from
`b861dd7` (main after the post-merge fix branch) into
`~/Library/R/4.0/library`; exports 56/30/31/31/16/18/15/11/9 = 217.
`llm_prompts/` regenerated from that library (`d4bded6`); **TaxaWizard 1,070
pass / 0 fail** -- both library-dependent tests now green. Trap hit once and
recorded: `R --vanilla` ignores the user library, so a path lookup under
`--vanilla` returns nothing; never use it to locate installed packages.
Post-merge fix branch also landed: `migrate_reference_cache()` deleted,
`suggest_unreferenced_species(data_type=)` required (callers updated in
TaxaAssign, its vignettes and 13 tests; none external), 16 A3 rewordings,
acoustic/image examples added to `score_consensus()`, `join_priors()`,
`posterior_consensus()`, `workflow_engine()`, `sniff_input()`.

## 7. Stage B -- verification (frozen tree, at `pre-1.0-freeze`)

**Entry conditions -- all true, verified, before B1:**
1. No session other than the screen's is editing TaxaID; the workflow chat is
   on its branch.
2. All three repositories (TaxaID, `~/My Drive/Rscripts/eDNA/`,
   `~/My Drive/Stats and Data/GreatLakes data/`) clean and committed.
3. All nine packages `devtools::check()` clean and reinstalled from the tag,
   build timestamps read from the installed `DESCRIPTION`, not assumed. Never
   reinstall while another R process has the package loaded.
4. NCBI healthy (a throttled NCBI is indistinguishable from several defects).
5. Stage A closed, with every *decide* answered.

- **B1. Clean-checkout reproducibility.** Clone the tag to a fresh directory
  with a fresh `R_LIBS_USER`, install in dependency order, `devtools::test()`
  (never bare `test_dir()`) every package. Nothing may depend on state that
  exists only on the author's machine.
- **B2. Every number reproduces.** Each figure in the README, the supplemental
  methods and the manuscript traced to a run that still produces it. The
  recurring failure here is a number true when written and silently stale
  after; the 2.01M-vs-8.11M GBIF row count is the canonical case.
  **Enumeration DONE 2026-09-21** (`scratchpad/B2_numbers.md`, preserved in
  `TaxaID_dev/screen_records/`): ~51 measured numbers -- 6 class A
  (fixture-reproducible), ~30 class B (warm production run), ~8 class C
  (cold network), 7 class D (no locatable producer). Structural finding:
  most GreatLakes/PtCon validation figures exist ONLY as console output typed
  into a document -- no file on disk holds 564, 0.868, 3.659 or their kin.
  **Standing rule from here: a validation claim is written to a file by the
  run that produced it, or it is not published.** Three "Lamar precision"
  figures are three pipeline stages (0.868 kernel-only, 0.818 coverage
  floor + EB, 0.872 full pipeline) cited in three documents without saying
  so -- label each by stage. Shortest covering set of runs: GreatLakes
  consensus workflow (kernel branch, warm, outputs SAVED), the Lamar
  comparison rebuild, PtCon 12S warm, Mugu warm (user decision: all three
  sites), one deliberate cold NCBI reference fetch first, and the external
  API round trips (BOLD/DataONE/PR2/WoRMS). Decisions 2026-09-21: freeze
  NOW (tag after the user's README pass); runs launched by the coordinator
  as background Rscript with the user on call for interactive stops;
  version 1.0.0, tag `v1.0.0`.
  **Revised 2026-09-21 (user):** GreatLakes is NOT in the manuscript; **PtCon
  12S is**, and the user holds its numbers. B2's reproduction target is
  therefore PtCon 12S (one run, isolated `OUT_PREFIX`, outputs saved);
  GreatLakes and Mugu become SUBSET code-path runs under the FAST convention
  (own `OUT_PREFIX`, read-only `REUSE_PREFIX`, no checkpoint of theirs ever
  reused; content-keyed caches shared). The mislabel reference screen is
  NOT re-run in B2: its verdict cache covers only a fraction of accessions,
  so it trips NCBI limits regardless, and it changed 6 of 13,442 hits at
  PtCon -- serve it from checkpoint (`SCREENS_FROM_CHECKPOINT`) or cap it.
  **Decision: the screen is OFF by default in the workflow template**
  (`SCREEN_REFERENCE_ACCESSIONS = FALSE`), on by flag, with its yield and
  NCBI cost stated beside the flag.
  **PtCon 12S B2 run STAGED 2026-09-21** (awaiting the user's go): driver =
  `TaxaID_dev/screen_records/.../b2_runs/PtCon12S_b2_workflow.R`, a copy of
  `eDNA/PtConception/PtConceptionWorkflow_12S_single_site.R` differing in
  ONE line (`OUT_PREFIX <- "PtConMifishSchulte_b2"`); `SUBSET = FALSE`,
  `REUSE_PREFIX = NULL`, `SCREENS_FROM_CHECKPOINT = TRUE` with the three
  production screen checkpoints (match_eval, ref_eval, removal_audit; Sep
  11) copied under the b2 prefix so no BLAST runs; reference-sequence fetch
  cold once; GBIF pool re-downloaded once under hashed names; LLM steps
  warm where cached. Non-interactive stops: `apply_spatial_review_decisions()`
  runs from the saved decisions file (and will report ambiguous points),
  `review_spatial_flags()` and the `interactive()` block are skipped under
  Rscript, `on_unreviewed = "error"` at Step 8 can halt the run. Launched as
  a background Rscript against the installed library from `3909ae6`;
  outputs land as `PtConMifishSchulte_b2_*` beside the production files.
- **B3. The structural guards fire.** Break each deliberately and confirm it is
  caught: vignette-call checking, snippet/graph-edge export checking, the
  sampling-group kingdom guard, `cache_ok()` staleness inputs, `on_unreviewed
  = "error"`, `on_count_failure`.
  **DONE 2026-09-21** (`TaxaID_dev/screen_records/.../B3_guards.md`): eleven
  guards broken one at a time in a scratch worktree; **9 of 11 fired** with
  a real failure. Two gaps, both TaxaWizard tests, fixed in its B4 pass:
  the word-boundary invariant test asserted only the " ..." marker (a hard
  mid-word cut with the marker appended passed); the committed-template
  diff test carried `skip_on_cran()` and silently skipped under a bare
  `test_file()` -- the file's strongest guard as a no-op, the exact shape
  this project forbids. Rule: a guard test never `skip()`s for a reason
  that is not provable at run time; it `fail()`s with the reason.
- **B4. Per-package checklist passes 1-7** (memory `pre-code-review-package-
  checklist`) on every package, including `/security-review`.
  **Before B4 started (2026-09-21)**: the three post-screen follow-ups landed
  (`verify_local_corroborations()` reads the audited run's key; the literature
  cache's character-sum checksum is `rlang::hash()`; iNaturalist's omitted
  `captive`/`quality_grade` verified live = "any": 470,344 / 470,344 /
  434,444), plus `force=` on all five `*_clear_cache()` wrappers, the
  clear-cache tests rewritten to the containment contract, and
  `.gbif_dl_meta_path()`'s equal-sum checksum replaced by `rlang::hash()`
  (existing GBIF download entries become misses; user's disposable-cache
  decision). Real caches verified to PASS the containment check (TaxaFetch 20
  files / 2.7 GB, TaxaLikely 27,881 files). Sibling to fix in TaxaFetch's B4:
  `.gbif_checkpoint_path()` in `fetch_gbif_occurrences.R` has the same
  checksum shape. B4 runs one agent per package, two at a time, branch
  `stageb-b4-<Pkg>`; passes 1-6 executed, pass 3 report-only (no renames),
  7a light read of pre-review functions, 7b done by the A5 template review.
  **TaxaMatch DONE** (`784adcf`): `check()` 0/0/0, 1,368 tests; 61
  non-ASCII characters replaced; `@examples` added to the 10 exports that
  had none (one draft example corrected -- `evaluate_reference_accessions()`
  does not return `reference_action`); stale `.lintr` exclusions removed;
  **`Depends: R (>= 4.1.0)` added** -- the package uses the native pipe but
  declared no minimum R (check every package's DESCRIPTION for the same).
  7a: no `system()`/`eval()`/`parse()` in pre-review code; the local-BLAST
  argument string is built from numeric and literal-set values only.
  **TaxaAssign DONE** (`270337e`, `18c68f0`): `check()` 0/0/1 (timestamp
  NOTE), 811 tests; 87 non-ASCII replaced; **50 auto-extracted scratch
  files under `tests/testthat/_problems/` deleted** (called a helper that
  exists nowhere; committed by accident in an earlier lint sweep); stale
  `.lintr` exclusions for the moved `suggest_unreferenced_species` removed;
  `Depends: R (>= 4.1.0)` added by the coordinator. 7a: no I/O of its own;
  one `eval()` on a function's own default-argument expression, guarded;
  LLM prompts take free text unescaped (same shape as TaxaFlag) but both
  parsers treat the reply as typed data with fallbacks -- worst case a
  biased prior, never execution. Design note for 1.1: delimit free-text
  fields in LLM prompts consistently across TaxaAssign, TaxaFlag,
  TaxaLikely, TaxaHabitat.
  **TaxaFetch DONE** (`14fea3f`): `check()` 0/0/0 (no NOTE), 840 tests;
  `.gbif_checkpoint_path()` checksum -> `rlang::hash()` (old checkpoints
  become misses); `Depends: R (>= 4.1.0)`; tests' non-ASCII fixed; drifted
  `.lintr` lines re-verified one by one. 7a: every user-derived cache path
  hashed or sanitised; URLs `URLencode`d; DataONE downloads gated by a host
  allow-list. **One item for the pre-tag fix pass**: `.pasta_eml_url()`
  (dataone_occurrence_search.R ~626) splices `dataset_id`'s dot-split
  segments into a URL path with no character allow-list -- fixed host, so
  not SSRF, but `/` or `..` in an id changes the requested path; apply the
  `[A-Za-z0-9_-]` sanitiser used in `literature_search.R`.
  **Template default MERGED (`ae25da1`)**: `SCREEN_REFERENCE_ACCESSIONS <-
  FALSE` in the generated template, rationale in Step 1's comment (one BLAST
  round-trip per accession trips NCBI; 6 of 13,442 hits changed on a real
  12S study; run as a separate task).
  **TaxaTools DONE** (`f097ece`): `check()` 0/0/0, 1,174 tests; 94 non-ASCII
  lines fixed incl. an em-dash inside a live `message()` format string; two
  never-read variables deleted; **security fix: Gemini's API key travels in
  the request URL, and `call_api()`'s connection-error handler echoed the
  raw message (URL included) through `stop()` -- the key is now redacted
  before the error surfaces**; no key ever written to a manifest or cache.
  Online name-verifier tests ran for real and passed. Not done, by
  judgement: dated comments in `tests/` (outside A1's scope; tests ship but
  are not user-facing prose) -- decide whether a tests/ sweep is wanted.
  **TaxaLikely DONE** (`882c2cc`): `check()` 0/0/0, 1,335 tests. **It found
  a check() ERROR introduced by A7**: `identify_confident_observations()`
  became internal but its `@examples` still called it unqualified -- the
  example run failed with "could not find function"; fixed with `:::`.
  Lesson for any future internalisation: re-run the examples, not just the
  tests. Also: an `@examples` block added to `check_cross_genus_sampling_
  noise()`; drifted `.lintr` lines re-verified; 9 `object_usage_linter`
  false positives confirmed with `codetools::checkUsage()` (cli glue). 7a:
  cache filenames sanitised (`[^A-Za-z0-9]` -> `_`); no `system()`/`eval()`.
  **TaxaExpect DONE** (`2658f3c`): `check()` 0/0/0 (no NOTE), 701 tests;
  `@examples` added to the five exports that had none (all run under
  `load_all()`); `Depends: R (>= 4.1.0)`; 32 lint findings fixed. Naming
  inconsistencies REPORTED for 1.1, not fixed: `lat`/`lng` in the two
  API-facing generators vs `site_lat`/`site_lon` in the kernel math;
  `sampling_group` (a value) vs `sampling_group_col` (a column). **Process
  rule learned: never `git stash` in a shared-repo worktree** -- worktrees
  share one stash list and the agent popped the workflow chat's WIP stash
  by mistake (restored intact, verified); compare against a baseline with
  `git archive <commit> | tar -x` instead.
  **TaxaFlag DONE** (`90dcf8a`): `check()` 0/0/0 (no NOTE), 580 tests;
  8 non-ASCII fixed; dead `n_bad` removed; stale `.lintr` entry for the
  removed `build_review_covariates.R` dropped; examples run explicitly.
  7a: review cache keyed by hash with the full key re-verified on read; the
  gadget renders via `shiny::p()` (auto-escaped), never `HTML()`.
  **TaxaHabitat DONE**: `check()` 0/0/0 (no NOTE), 580 tests; the three
  roxygen link warnings fixed; `@examples` added to `save_/apply_spatial_
  review_decisions()`; a U+241F glyph used as an in-memory join delimiter
  replaced by the ASCII `\x1f` control character (behaviour verified
  identical); **`flag_habitat_inconsistencies()` now re-attaches the
  `habitat_proportions` attribute explicitly** -- a comment promised it and
  a test asserted it, but the attribute survived only because `left_join`
  happens to preserve attributes on a plain data frame. NOAA and Natural
  Earth downloads ran live and passed.
  **TaxaWizard DONE (`3909ae6`) -- B4 COMPLETE FOR ALL NINE.** 1,106 tests;
  `check()` 0 warnings / 0 notes with one ERROR that is the installed-library
  lag (the regenerated template was verified byte-identical against source
  via `load_all()`); 31 lints -> 0 (prompt-pack literals and a generated
  script line excluded with reasons); the two B3 gaps closed -- a direct
  unit test of `.truncate_at_word()` pins the word-boundary property, and
  `skip_on_cran()` is gone from the committed-template diff test. One
  curly-quote left in `test-registry.R:382` on purpose: it is the pattern
  under test. Reinstall from `3909ae6` follows; TaxaWizard's test and
  `check()` are re-run against the fresh library as the B4 closing check.
  **Third reinstall DONE (from `3909ae6`; pack regenerated `c9d42f2`):
  TaxaWizard 1,107 / 0 -- the committed-template diff test passes against a
  current library with no skip.** `check()` still shows ONE error, and it
  is the B3 fix working: under `R CMD check`'s isolated library path the
  snippet-drift test now reports `package_unavailable` for every sibling
  TaxaID package instead of silently skipping. Diagnosis-and-fix in
  progress: the honest outcome is a `skip()` only when `requireNamespace()`
  provably fails, and a run (not a skip) whenever the siblings are present.
  **B1 DONE 2026-09-21** (clone of `main` at `c9d42f2`, fresh library first
  on `R_LIBS`, all R steps confirmed resolving under it): all nine packages
  install in dependency order with zero warnings and no undeclared
  dependency; eight suites pass at baseline (TaxaTools 1174, TaxaFetch 844,
  TaxaMatch 1368, TaxaLikely 1335, TaxaExpect 701, TaxaHabitat 580,
  TaxaAssign 811, TaxaFlag 580; 0 failures); no hard-coded machine paths,
  every `system.file()` target present in the installed copies; both README
  smoke tests run to `OK` from the fresh install with only the documented
  warnings. **One real defect**: TaxaWizard 1098/9 -- `test-pack.R`'s
  "generated pack equals the committed copy, date stamp aside" fails on
  every clean install because the pack embeds `packageDescription()$Built`
  (second-precision) in the packages table and every `CONTEXT_<pkg>.md`
  header, and `.undate()` excuses only the calendar date. The committed
  pack only ever matched because it was regenerated seconds after the
  install that produced it. Decision: the Built stamp leaves the pack (a
  user-facing document carries the version, not an install wall-clock);
  fix goes on `stageb-wizard-check` with the `check()` fix below. Report:
  `TaxaID_dev/screen_records/.../B1_clean_clone.md`.
  **TaxaWizard `check()` fix (branch `stageb-wizard-check`, `c430a83`)**:
  cause confirmed -- `R CMD check` builds an isolated library from
  DESCRIPTION alone, and seven siblings were undeclared, so the drift test
  ran against a TaxaTools-only registry; and the test's skip fired only at
  ZERO installed siblings. Fix: the seven added to `Suggests`; the skip is
  now per-package and names what is missing. Verified: with siblings
  present the drift test RUNS (1107/0, SKIP 0); with only TaxaTools
  resolvable it skips provably (not fails); `check()` 0/0/0. **Built stamp
  removed** from the pack (`b8ec71a`: packages table is Package | Purpose |
  Version; each header reads "Version x. n exported function(s)."), pack
  regenerated, 1107/0 with SKIP 0, `check()` 0/0/0. **Both MERGED to main
  `c8d1e15`.** The installed TaxaWizard (3909ae6 build) is now behind main
  in `R/pack.R` only; the pre-tag reinstall covers it.
  **Pre-tag fix MERGED (`e9efe23`)**: `.pasta_eml_url()` holds each id
  segment to `[A-Za-z0-9_.-]` with no `..` (34 DataONE tests pass).
  **B3 launched** (scratch worktree, nothing committed): eleven guards each
  broken deliberately and observed -- vignette-call checks, snippet export
  validation, the placeholder-declaration and committed-template tests, the
  registry invariants, the kingdom guard, `cache_ok()` staleness,
  `on_unreviewed = "error"`, `on_count_failure`, cache-clear containment,
  the decision-file schema and ambiguity guards.
- **B5. USGS release checklist** in `usgs_release_review/` with its response.
  **Checked 2026-09-21 against the tracked tree** (every row of
  `RESPONSE_to_release_review.md` re-verified, not read): README title uses
  the colon; `code.json` present, CC0-1.0, `status` Preliminary, version
  0.1.0, `laborHours` 0, `repositoryURL` kdlafferty/TaxaID, lastModified
  2026-06-27; zero LICENSE/DISCLAIMER files inside packages, zero
  disclaimer mentions in package READMEs, one of each at the root; zero
  tracked residue (renv, roadmap, TODO, git-setup, INTRO, qmd,
  PACKAGE_SETUP, DESCRIPTION.md); ECOSYSTEM_WORKFLOW.md linked from the
  README; CLAUDE.md in all nine `.Rbuildignore`s; 174 test files (response
  corrected from 173, `f2c8e32`). **Two process facts from
  `WERC_Software_Checklist.pdf` that bear on the tag**: (1) a PROVISIONAL
  release "may not be cited or referenced by other official USGS
  Information Products (e.g., manuscripts)" -- the PtCon 12S manuscript
  cites TaxaID, so the manuscript needs the OFFICIAL release path (IPDS
  record, reserved DOI, technical code + domain review, RM and CD
  approval); (2) the official path wants a RELEASE-CANDIDATE BRANCH named
  for the version (`1.0.0`), and WERC creates the immutable tag on their
  GitLab, so the local step is "branch `1.0.0` from main" rather than
  "tag `v1.0.0`" unless the user wants both. The official DISCLAIMER and
  `code.json` `status` change only when that path completes.
  **User decisions 2026-09-21 evening**: this version is the
  PRE-SECURITY-REVIEW submission, not a release -- no tag, no version bump,
  no `1.0.0` branch from this chat; the USGS path does those later.
  `repositoryURL` = `kdlafferty/TaxaID` (README, CITATIONs and two
  TaxaWizard strings aligned, `bae1d99`). The maintainer's own README pass
  (all ten READMEs, TaxaExpect figure replaced by `PisasterTheta.png`) was
  applied from the shared checkout onto branch `readme-user-pass`
  (`f461386`); style rules for the review: no em dashes, no ` -- `, no
  bold or italics outside headings, no LLM-style prose, shorter where
  possible, typos and factual errors fixed. Verification asked for: the
  TaxaAssign wrappers `run_bayesian_pipeline()`/`run_llm_pipeline()` and
  every inst/ and production workflow after the data removals; the
  TaxaWizard README's "three ways" claims; the TaxaFlag README's focused
  controls text; the TaxaExpect pooling claim (sharpened, `c3b83bc`: exact
  invariance when every candidate of an observation is rescaled alike).
  The maintainer also asked for a SECOND LOOK at the six `*_clear_cache()`
  functions, which read as redundant in the READMEs.
  **Wrapper and workflow verification DONE 2026-09-21**: every
  `Taxa*/inst/*.R` script and the template parse, reference only existing
  files and exported functions, and call none of the removed functions;
  the six production workflows (PtCon 12S single/multi, 18S, Mugu,
  GreatLakes, California Intertidal) parse with no dead reference into the
  repository tree (two stale prose comments outside the repo recommend the
  removed `migrate_reference_cache()`; Mugu's unreachable GLMM branch calls
  a long-removed `add_pca_covariates()`). `run_llm_pipeline()` intact.
  `run_bayesian_pipeline(generate_report = TRUE)` was BROKEN: it spliced
  `score_transform` into the `generate_report()` call, which has no such
  formal. FIXED (`7172151`): the value travels as the `report_params`
  attribute, both wrappers validate `report_params` names up front, and a
  real run's Methods text now names the square-root-mismatch transform.
  Also found: the shipped fast fixtures still carried the retired
  `resident_observed` label (18S priors 1,522 rows, 12S r2 479, Mugu
  posterior 116), so the 18S and Mugu smoke tests failed under the closed
  `prior_branch` set introduced by this screen; relabelled and re-run
  (18S 813 rows, Mugu 0.3 s). Three graph snippets and the template still
  listed the label; removed. The template guard test regenerated in a
  subprocess from the INSTALLED snippets, so it could not see source
  edits; the generator now reads the repository's graph and snippets and
  a stale template provably fails the guard. The fixture README was a
  205-line dated development log shipped in `inst/`; rewritten as an
  inventory. All merged to main (`6b2e758`); TaxaAssign 815/0, TaxaWizard
  1107/0. The installed library is now behind main in TaxaAssign and
  TaxaWizard: reinstall before submission.
  **README pass COMPLETE and MERGED (`287a219`)**: all ten READMEs read
  by a second pass under the maintainer's rules (no em dashes or ` -- `,
  no bold/italics outside headings except scientific names and journal
  titles, plain prose, no chronology), every function, argument, default,
  path and link verified against NAMESPACE/`formals()`/the tree, and the
  whole-tree grep is 0/0/0 on every file. Factual errors caught and
  fixed: root (a `wi_output` reader that does not exist, a glmmTMB licence
  claim for a dependency TaxaExpect no longer has, Biostrings needed by
  `trim_to_amplicon()` too); TaxaLikely (examples calling
  `fetch_ncbi_reference_sequences(rank=)` and `compute_posterior(priors_df=)`,
  neither exists); TaxaFlag (score described as a mean of proportions; the
  code computes a depth-weighted rate ratio shrunk toward 0.5 by
  `prior_weight`); TaxaFetch (cache prompt threshold is 5 GB not 1 GB;
  overwrite prompt only with `allow_prompts = TRUE`); TaxaHabitat
  (`flag_habitat_inconsistencies()` flags, not `review_spatial_flags()`;
  `build_habitat_prompt()` needs no key); TaxaTools (Azure OpenAI provider
  omitted; `.onAttach()` auto-detect is interactive-only); TaxaWizard (the
  three routes stated as the code has them); TaxaExpect (pooling claim
  made exact; *Pisaster ochraceus*). Reports in
  `TaxaID_dev/screen_records/.../readme_pass/`. Flagged, not changed:
  `assign_scores()` bullet omits `score_type = "direct"`; `cache_ok()`,
  `assign_sampling_group()`, `fetch_worms_attributes()` unmentioned in the
  TaxaTools README; AZURE_OPENAI_API_KEY absent from the root API-key
  table; `resolve_review_overrides()`/`verify_local_corroborations()`
  unmentioned in TaxaMatch's README.
  **Coordination 2026-09-21 night**: the workflow chat has a detached
  Rscript (CalIntertidal Sections 6-7, cold NCBI fetch, ~7 h) holding the
  library until ~02:30 on 2026-09-22; NO REINSTALL before it lands. The
  shared checkout still carries the maintainer's README edits uncommitted
  on the workflow branch; proven lossless against main (seven files
  byte-identical to `f461386`, the other three differ only in the three
  conflict hunks where main's later corrections won), so they can be
  stashed (`git stash push -- README.md Taxa*/README.md`) before that
  branch next merges main. The workflow chat's untracked
  `ecosystem_docs/REENTRY_PROMPT_theta_surface_options.md` is theirs.
  **2026-09-22 decisions**: main PUSHED at `1b7f314`; cache functions =
  OPTION B (API unchanged; each package README states its
  `<pkg>_clear_cache()` in one sentence pointing at the root README's
  Caching and resources section, which is the single full description);
  every package README must list EVERY export (a grep against NAMESPACE
  found 61 unmentioned across eight packages; being added with one-line
  purposes from roxygen); merge, push and reinstall decisions sit with the
  screen session, not the workflow chat; TaxaAssign + TaxaWizard reinstall
  after the CalIntertidal run lands.
  **DONE 2026-09-22**: all nine package READMEs list every export (61
  added; the NAMESPACE-vs-README grep prints nothing for all nine);
  option B applied (one cache sentence per package, root README's Caching
  and resources holds the five-function shared signature, the engine's
  containment rule and `taxaid_cache_report()`); `assign_scores()` lists
  `score_type = "direct"`; `AZURE_OPENAI_API_KEY` in the key table;
  whole-tree style grep 0/0/0 on all ten. Reports in
  `TaxaID_dev/screen_records/.../readme_pass/complete_{A,B}.md`.
  **KNOWN DEFECT reported by the workflow chat 2026-09-22, NOT fixed in
  this screen (the maintainer assigned it its own chat)**:
  `TaxaLikely::fetch_ncbi_reference_sequences()` queries NCBI by name with
  no lineage constraint, so a homonym resolves to whichever node the
  `[ORGN]` search prefers. Live: the red alga *Vertebrata* (taxid 1261581)
  pulled 306,181 vertebrate sequences (taxid 7742, a clade), 28% of a
  1.1M-sequence COI reference set, and returned no Rhodophyta at all; 78
  genera with lineage disagreement, ~11 true homonyms (Vertebrata,
  Digenea, Grania, Contarinia, Acrotylus, Ptilophora, Mastophora, Galene,
  Lobophora, Bulla, Ctenophora, Armadillo), the rest genuine
  reclassifications that must be accepted. Rank alone is not enough
  (*Lobophora* has two genus-rank nodes); the fix needs rank AND lineage
  and probably a signature change: a 1.0 API decision. The empty result
  reads downstream as "no barcode", not "malformed query". Write-up:
  `ecosystem_docs/REENTRY_PROMPT_homonym_detection.md` (untracked, in the
  shared checkout). Same shape as the Polychaeta homonym found 2026-09-15.
  **Shared checkout refreshed 2026-09-22** (`f016809`, main merged into
  `workflow-ptcon-multisite` after the workflow chat's verified all-clear;
  tree identical to main; the maintainer's next README round happens
  there). Two stashes sit in that checkout, NEITHER the workflow chat's:
  stash@{0} = the maintainer's first-round README copies (proven lossless
  vs main); stash@{1} = this screen's own 2026-09-20 draft (510-line
  screen doc, since committed and grown to 1,129 lines on main) plus a
  one-line CLAUDE.md path that main already has in its moved form. Both
  superseded; DROPPED 2026-09-22 on the maintainer's word. Reinstall hold still on.
  **Freeze exception granted by the maintainer 2026-09-22**: the
  theta-surface thread may edit `TaxaExpect::plot_theta_surface()`
  (rendering only: `theta_range`, `palette`, `bg`, `support_panel`/`fade`,
  mask outline, and the static branch's missing colour key). Conditions
  from this screen: no new export and no change to any prior or number;
  branch off main, commit as you go, merge only through this session;
  roxygen and README free of chronology; `devtools::document()`,
  `test()` and `check()` 0/0/0 before merge; the `alpha_by_n_eff` logical
  stays accepted if `fade` supersedes it; `llm_prompts/CONTEXT_TaxaExpect.md`
  embeds the signature, so after the TaxaExpect reinstall the pack must be
  regenerated and its drift test re-run; the TaxaWizard snippet
  `std_to_priors_kernel.R` calls it with `taxon` only, so additive params
  need no snippet or template change; the README figure
  `PisasterTheta.png` was rendered with the old palette and background
  and should be re-rendered under the new defaults or its caption kept
  palette-neutral. No conflict with this screen's plans: no version bump,
  NAMESPACE or NEWS change is scheduled here (pre-security-review
  submission). Reinstall of TaxaExpect goes through the same hold.
  **Homonym fix BUILT by a separate thread 2026-09-22, branch
  `homonym-detection` (off `e01032d`, tip `24775ad`), NOT merged, NOT
  pushed.** TaxaTools gains `R/ncbi_homonyms.R` with THREE NEW EXPORTS
  (`resolve_ncbi_taxid()`, `check_lineage_agreement()`, and a 12-row data
  frame `known_ncbi_homonyms`); `fetch_ncbi_reference_sequences()` gains
  an opt-in `taxa_lineage` (NULL reproduces the old behaviour). Live
  verified: 68/68 Rhodomelaceae for *Vertebrata* with the guard. Tests
  TaxaTools 1209/0, TaxaLikely 1358/0, check 0/0. Rule 1 of the freeze
  applies: the maintainer decides the exports. Screen's recommendation:
  export the two functions (a generic mechanism the `verify_taxon_names()`
  bypass will need too), do NOT export the 12-name list (it is what one
  fetch found, will go stale, and the resolver is the mechanism; keep it
  as test fixture or vignette example). Merge conditions: Micah-template
  review + "Added after the review" entries in both review responses;
  TaxaTools README lists the new exports (completeness rule); pack
  regenerated after reinstall; merged through this session. Left
  unfixed by design: priority_taxa path unwired; `verify_taxon_names(
  backbone_id = 4)`'s own NCBI bypass has the same collision (separate
  decision). **REINSTALL DISCLOSURE**: that thread ran devtools::install()
  for TaxaTools (09:45:53 local) and TaxaLikely (10:01:27) UNDER the
  workflow chat's live 12S run (pid 73144, started 09:12:47), before it
  knew of the hold; the workflow chat has been alerted to check the run.
  The installed TaxaTools and TaxaLikely are therefore an UNMERGED branch
  build, not main; the pre-submission reinstall must rebuild all nine
  from final main regardless.
  **Consequence confirmed by the workflow chat**: its 12S run (pid 73144)
  is VOID; the packages were swapped under it at 09:45:55 and 10:01:29,
  no open handle kept the old .rdb, and evaluate_likelihoods ran through
  the swap. No error surfaced, which is the documented failure mode.
  Its output is being kept renamed `*_SUSPECT_branchbuild.rds` as a
  comparison baseline only. Plan agreed: on that chat's "run ended"
  message this session verifies no R process holds the library (ps/lsof,
  including the homonym thread's R and any rsession) and rebuilds ALL
  NINE packages from main in dependency order, verifies Built stamps and
  suites, then clears both the 12S re-run (~40 min, cache on disk) and
  the homonym thread. Second independent instance of the shared-library
  hazard in this screen; the structural fix (per-session R_LIBS_USER)
  is recorded in memory, not built.
  **Homonym fix MERGED `5ef58e6` and pushed**: the maintainer took the
  screen's recommendation; the thread un-exported the list
  (`.known_ncbi_homonyms`, test fixture and help-page example), added the
  two exports to TaxaTools' inventory and "Added after the review"
  entries to both review responses. Reviewed from a detached worktree:
  TaxaTools 1209/0, TaxaLikely 1358/0, check() 0/0 on both. TaxaTools
  now has 58 exports. The shared checkout, which that thread had switched
  to its branch, is back on `workflow-ptcon-multisite` with main merged
  (`3ae739f`), tree identical to main. Remaining from this thread, own
  decisions later: `verify_taxon_names(backbone_id = 4)` bypass; the
  priority_taxa fetch path; `audit_barcode_coverage()` and
  `suggest_unreferenced_species()` not wired to the resolver. After the
  rebuild: regenerate `llm_prompts/` (CONTEXT_TaxaTools and
  CONTEXT_TaxaLikely embed the changed signatures).
  **LIBRARY REBUILT 2026-09-22 10:38 local from main `7a1467b`**: pre-flight
  clean (no R process, no open handle, worktree clean); all nine installed
  in dependency order, Built stamps 17:38:03-17:38:26 UTC, export counts
  58/30/31/31/16/18/15/11/9; prompt pack regenerated from it and
  committed; TaxaWizard 1107/0 against the installed siblings; the three
  offline smoke tests OK from the installed copies. Both chats cleared:
  the workflow chat re-runs 12S clean (~40 min) and diffs it against the
  quarantined branch-build baseline; the homonym thread may install
  again. The void run finished NORMALLY with zero errors: the hazard is
  that a reinstall under a run does not crash it.
  **Follow-up MERGED**: `audit_barcode_coverage()`/`audit_reference_coverage()`
  had the same unguarded `res$ids[1L]` genus-taxid pick; now resolved
  through `TaxaTools::resolve_ncbi_taxid()` with lineage terms built from
  the caller's own rank columns, no new parameter, no export change;
  TaxaLikely 1371/0, check 0/0/0; reviewed from a detached worktree.
  Deliberately unwired (query volume, species-level names collide far
  less): `suggest_unreferenced_species()` per-species counts and the
  priority_taxa path. Installed TaxaLikely is now behind main by this
  internal change; reinstall at the next safe window, not urgent.
  **PROPOSAL awaiting the maintainer**: `verify_taxon_names(backbone_id = 4)`'s
  backend `.verify_via_ncbi()` overwrites `name_to_taxid[[name]]` per
  returned summary, so a name with two NCBI nodes gets whichever came
  last, silently; it sits under `escalate_taxonomic_rank()`,
  `fill_higher_ranks()` and `assign_sampling_group(harmonise = TRUE)`.
  Option 1: ambiguous name -> NA with a warning naming the candidates
  (honest gap, existing not-found paths fire). Option 2: an
  `expected_rank` hint on `verify_taxon_names()` used as the rank
  discriminator (signature change, three callers). Screen's view: 1
  now, 2 later, and the NA must be accompanied by a warning that lists
  the name and its taxids so a user can pass the right one downstream.
  **Maintainer's DECISION 2026-09-22**: neither option as proposed. An NA
  plus a warning invites a large silent failure in big batches; the user
  must CHOOSE, in one batch. Spec sent to the homonym thread: collect all
  ambiguous names with candidate taxids and lineages; interactive = one
  prompt for the whole batch with numbered candidates and an explicit
  "skip"; non-interactive = stop with the same table and instructions;
  choices are a decisions input (data frame or file, the spatial-review
  decisions convention) that `verify_taxon_names()` accepts and the
  prompt saves; "skip" is the only route to NA and is recorded; the
  three callers pass decisions through. One-argument signature addition
  accepted; any save/apply helper names to be proposed before export.
  Rulings on the thread's proposal: `decisions = NULL` (data frame or
  .rds path) approved, warned-as-unused for other backbones; the
  save/apply helpers stay INTERNAL (no new exports: a two-column data
  frame and `saveRDS()` are the API); NO default persistence location
  (a hidden decisions file is state that changes results without
  appearing in the script, the stale-cache shape again); the
  non-interactive stop prints a ready-to-paste `decisions =
  data.frame(...)` skeleton with candidates as comments; interactive
  saves only to a path the user named, else prints pasteable code; a
  new ambiguity not covered by supplied decisions is treated as
  unresolved, never guessed.
  **BUILT AND MERGED** (`verify-taxon-names-decisions`, tip `c7af511`):
  no new exports; `decisions` on the four functions; internal
  save/apply helpers; no default file; 45 offline tests; TaxaTools
  1250/0 (+1 network skip) from a detached worktree, check() 0/0/0.
  Installed TaxaTools and TaxaLikely are now behind main (this and the
  coverage-audit fix); reinstall both, then regenerate the pack
  (CONTEXT_TaxaTools embeds the four changed signatures), at the next
  window with no R process alive.
  **theta-surface-render MERGED** (maintainer approved both deviations
  2026-09-22): `plot_theta_surface()` gains `theta_range` (default
  "shared"), `palette` ("YlOrRd"), `bg` ("grey92"), `support_panel`
  (TRUE), `support_field`, mask outline and a colour key on both renders, a
  `layout(1)` reset; `alpha_by_n_eff` REMOVED (no caller anywhere;
  n_eff is scale-invariant so opacity misread extrapolation as
  confidence). TWO NEW EXPORTS approved: `as.data.frame()` method for
  the surface and `theta_surface_at()`. Landed with the screen's edits:
  one roxygen chronology line removed, review-response entries for both
  functions and the behaviour change, README section "Reading values
  off a surface" plus both in the function list (completeness grep
  clean, style 0/0/0). TaxaExpect 724/0, check 0/0/0. README figure
  kept as is by the maintainer's decision. Installed TaxaExpect now
  behind main too: the next reinstall window covers TaxaTools,
  TaxaLikely, TaxaExpect and the pack (CONTEXT_TaxaExpect embeds the
  old signature).
  **LIBRARY REBUILT AGAIN 2026-09-22 14:05 local from main `f5a01c0`**
  (maintainer quit both RStudio sessions; pre-flight clean): all nine,
  Built 21:05:33-21:05:55 UTC, TaxaExpect now 17 exports; pack
  regenerated (`c7d5846`, pushed; `alpha_by_n_eff` gone from it,
  `decisions` and `theta_surface_at` present); TaxaWizard 1107/0
  against the installed siblings; three smoke tests OK. Installed
  library == main for every package.
  **Four findings from the workflow chat's wiring of the new APIs
  (2026-09-22 evening), acted on**: (1) `check_lineage_agreement()` was
  DEFEATED by a shared root: "agrees" on any shared term, so full
  NCBI-style lineages agreed on "Eukaryota" for a red alga and a bat.
  FIXED: an `ignore` argument (roots and kingdom-level groups by
  default; `character(0)` restores the old rule) and a section stating
  that a disagreement is a review candidate, not a filter. (2)
  Family-level disagreement cannot separate a homonym from a benign
  revision (~12 of 78 on the real COI set): documented in the same
  section. (3) A homonym can present as ZERO results, invisible to any
  lineage check: `fetch_ncbi_reference_sequences()` now names the
  requested taxa that returned nothing (message + attribute
  `taxa_without_sequences`, also on the all-empty early return). (4)
  `max_per_genus` drops whole species and biases the between-species
  terms; documented, `max_per_species` preferred. The chat's own first
  wiring passed data frames and the error was swallowed by its tryCatch;
  the type error now says what to pass. TaxaTools 1260/0, TaxaLikely
  1371/0, check 0/0/0 both; merged to main. Installed TaxaTools and
  TaxaLikely are behind main by this change; reinstall after the
  workflow chat's COI run lands, then regenerate the pack.
  **CI (GitHub Actions R-CMD-check) had been RED on every push since
  `b2a27d4` (2026-09-21), TaxaWizard only; the maintainer noticed via the
  failure emails.** Cause: the checkpoint-invalidation tests added in the
  screen run a generated script whose Step 0 refused to run because
  `workflow_check(edges = )` reported Biostrings/DECIPHER as "missing"
  regardless of what the selected edges needed, and the runner has no
  Bioconductor packages (the local machine does, so `check()` passed
  here: an environment proxy). FIXED `14b2233`: an absent optional or
  Bioconductor package is "warn" unless a selected edge requires it
  (`refs_to_matrix` still reports it missing; the whole-ecosystem check
  is unchanged); test covers both directions with `requireNamespace`
  mocked. TaxaWizard 1113/0, check 0/0/0. Lesson: a green local check is
  not a green CI; read the CI result after every push. Installed
  TaxaWizard is behind main by this change (internal), same reinstall
  window as TaxaTools/TaxaLikely.
  **Root README round 2 (maintainer's edits, carried onto main and
  proofed)**: 1,253 -> 1,077 lines. Related Software 212 -> 109 (Table 1,
  Table 1b and every named function kept); Interactive Workflow Designer
  section removed and its content folded into "Which Entry Point"
  (START_HERE + CONTEXT_TaxaID paste, workflow_create(), workflow_app());
  Data Outputs compressed to one table (details live in package READMEs);
  seven Pandoc `{.underline}` spans replaced with plain text (GitHub
  renders them as literal brackets); "precision and accuracy" ->
  "precision and recall"; Table 1 caption no longer attributed to
  Orsholm et al. (it is TaxaID's own comparison; the benchmark cite stays
  in the prose); START_HERE path completed. Verified: every script in the
  Workflow Scripts table exists, parses, and calls only exported
  functions (comments in three shipped scripts named a removed function
  or the wrong package; fixed); all nine vignettes exist; both wrapper
  examples use real arguments and both wrappers ran end to end this
  screen; template guarded by its test. NOT executed: the sixteen
  per-stage workflow scripts (they need real data and keys).
  **Staleness audit of the sixteen scripts + two wrappers + template
  (2026-09-22)**: an AST walk checked every named argument of every
  TaxaID call against current `formals()`. One real stale script:
  `TaxaFetch/inst/Merge_sources_workflow.R` passed
  `create_taxon_names(taxonomy_ranks =)` and `rename_cols(df =)`, both
  renamed long ago (now `rank_system =`, `input_df =`); FIXED. All
  others: arguments valid. Last-commit dates are not evidence (most were
  touched by this screen's sweeps). Software Inventory counts were stale
  (TaxaTools 56 -> 58 exports, 27 -> 29 tests; TaxaLikely 30 -> 31 tests;
  TaxaExpect 16 -> 17 exports); corrected, and a TaxaWizard test now
  compares the table with NAMESPACE and tests/ so drift fails CI (proved:
  a wrong count fails). "white lists" -> "regional species lists". The
  execution of the sixteen scripts with real data and keys is a separate
  chat: `TaxaID_dev/ecosystem_docs/REENTRY_PROMPT_workflow_scripts_verification.md`.
  **README rounds carried 2026-09-22 evening**: TaxaExpect README
  (maintainer's edits + the introduction folded into Overview and a new
  Assumptions subsection "Occurrence records are informative but
  biased"; `bb35355`); TaxaAssign README second round (`3e8f3ab`); the
  root README working copy in the shared checkout proved to contain ZERO
  edits beyond round 2 (diff against `8814f23` empty), so its fifteen
  three-way conflicts were all round-2 processing versus the old base
  and resolved to main. All three of the maintainer's patch sets are
  saved in `TaxaID_dev/screen_records/.../readme_pass/maintainer_*.patch`.
  Shared checkout refreshed: `6a26c36`, tree identical to main. Rule
  learned: refresh the shared checkout to main BEFORE the maintainer
  starts a round, not after; an editing base behind main turns every
  later round into a three-way merge.
  **Workflow-scripts verification chat, first report (2026-09-22 night)**:
  three script bugs fixed on its branch and merged (`c4e8601`: an
  undefined `.best_thresh`, an undefined `match_df`, `read_birdnet_output()`
  given a table instead of a path). Six package-level findings, acted on
  here (`1c03f4d`, then `site-priors-guard`): (1) a single-taxon habitat
  request comes back headerless from the model 3/3 times and parsed as
  zero rows; the parser now supplies the header from the prompt's layout
  when the field count matches. (2) `infer_exclude_predicted()` did not
  recognise `composite_id`, the accession column its own upstream
  writes; added. (3) `join_priors()` with a site that matches no prior
  rows: `run_bayesian_pipeline()` died in a bare vapply, and
  `join_priors()` itself completed SILENTLY with every candidate at the
  floor prior; both paths now stop with the grid ids / habitats the
  priors hold. (4) `generate_priors_workflow.R` is named by the tutorial
  chain but was never built: asked the chat to build it. (5) the FASTQ
  tutorial ran live DADA2 and an unconditional Bioconductor install on
  source; Step 0 is now opt-in (`RUN_DADA2`) with a guarded install.
  (6) the merge workflow saved its output INSIDE the installed TaxaFetch
  library; now beside the project. Lesson from this session's own slip:
  a commit chain must GATE on the test result; one merge went to main
  with two failing tests and was repaired within minutes, but CI is the
  backstop, not the check. Installed TaxaHabitat, TaxaAssign, TaxaLikely
  behind main by these fixes; reinstall at the next window.
- **B6. Licensing and provenance:** CC0 throughout, `code.json` status matching
  the release type, DISCLAIMER matching provisional vs official.
  **Checked 2026-09-21 (read-only):** `License: CC0` in all nine
  DESCRIPTIONs; one `LICENSE.md` and one `DISCLAIMER.md` at the root, none
  inside packages; `Depends: R (>= 4.1.0)` in all nine. **At the tag,
  four fields change together and need the user**: `code.json` `version`
  0.1.0 -> 1.0.0 and `date.lastModified` (2026-06-27 today); `code.json`
  `status` "Preliminary" and `DISCLAIMER.md`'s "preliminary or provisional"
  text -> the USGS approved-release wording IF the WERC review is signed off
  by then, else both stay provisional (they must agree with each other);
  `code.json` `laborHours` is 0 (USGS asks for an estimate); `code.json`
  `repositoryURL` must match the repository the release is published from
  (see the remote check). All nine `DESCRIPTION` `Version:` -> 1.0.0.

## 8. Findings to carry into the manuscript (not to fix)

- The Axis-1 `expected`/`unexpected` boundary is
  `median(taxaexpect_priors$theta_mean)` of the table being classified, so it
  **floats with the data** (11.7x shift at GreatLakes from refreshing evidence
  rows alone). Report the threshold with any `unexpected` count.
- `prior_branch` names the generator, not the evidence: within the kernel
  branch `effective_records` spans ~10 orders of magnitude (44.9% of PtCon 12S
  rows under one Kish effective record). No default gate.
- **The pipeline is deterministic**: byte-identical consensus across two full
  GreatLakes runs despite 1,000-draw Monte Carlo and no `set.seed()`, because
  the consensus reads `posterior_point_est`. State this in Methods.
- Kish `n_eff` is scale-invariant; down-weighting a group buys no uncertainty
  discount.
- **A workflow written after a package split can silently inherit the old
  behaviour the split warned about** (reported by the workflow chat,
  2026-09-21): the PtCon multi-site occurrence pool never called
  `dedupe_occurrences()`, so it counted reports rather than detection
  occasions -- 21,652,448 rows collapse to 947,674; Kish n_eff at one site
  falls from 8,428,948 to 231,127; the inflation over distinct points from
  191x to 6.6x; one coordinate had filed 263,385 rows. Every published
  pool-size or n_eff figure must state whether it is occasions or reports.
- **A workflow override discarded the reasoning a default carried** (same
  chat, 2026-09-21): the pool build passed `threshold = 0.5` to
  `assign_habitat_biological()` against its own roxygen warning; 15 habitat
  generalists -- every one a land-sea or fresh-salt boundary species, the
  wrong 15 for an intertidal study -- became unassignable. Restoring the
  documented 0.3 took Uncertain points from 13,207 to 0. A methods section
  should state every non-default argument a workflow passes.
- A test failing for a month is evidence, not furniture (the CoordinateCleaner
  `cc_zero(buffer=)` unit change made a null-island check a no-op for weeks
  while labelled "environmental").

## 9. Method notes

- Discovery on Sonnet, adjudication on the expensive model; a spend limit
  killed seven expensive agents mid-flight on 2026-09-13.
- Subagents in scratchpad worktrees commit as they go; the scratchpad dies
  with the session.
- Check the thing, not a proxy: open files rather than counting grep hits;
  read the installed build rather than the diff; `git log -L` rather than the
  current file. Ten defects in two days had the proxy shape.
- A chat's finding about another chat's work is itself a claim; verify it
  before propagating it (the "column never renamed" claim lived two sessions
  and produced dead code).

## 10. Execution plan

| order | pass | model | parallel with | needs user first |
|---|---|---|---|---|
| 0 | CLAUDE.md freeze block + memory entry; workflow chat to a branch | -- (this session) | -- | DONE 2026-09-20 |
| 1 | A7 zero-caller + catch-all lists | Sonnet x1 | A1, A3, A4 | -- |
| 1 | A1 metadiscourse (9 packages) | Sonnet x9, one per package, own branch each | A7, A3 | -- |
| 1 | A3 signal-neutrality table | Sonnet x1 | A1, A7 | -- |
| 1 | A4 hygiene inventory (no moves yet) | Sonnet x1 | all | -- |
| 2 | A2 legacy deletion | Sonnet x1 after A1 merges | A5 | `migrate_reference_cache()` decision |
| 2 | A5 catalogue + Micah template + response sections | Sonnet x9 + adjudication | A2, A6 | 3 WERC items |
| 2 | A6 README caching section | Sonnet x1 | A5 | -- |
| 3 | A4 moves, A8 claims scan | Sonnet x2 | -- | A7 decisions |
| 4 | tag `pre-1.0-freeze` | -- | -- | declare freeze |
| 5 | B1-B6 | Sonnet per package, adjudicated | -- | entry conditions |

Wave 1 is safe against the live workflow chat: none of it touches `TaxaFlag`,
`TaxaHabitat` code, only their roxygen -- and A1's TaxaFlag/TaxaHabitat agents
should wait until that chat's uncommitted edits are on its branch.

## 11. Definition of done

A written statement that Stage B ran against `pre-1.0-freeze` (and names the
commit of every post-tag package re-run), against named commits in the two
workflow repositories, with NCBI healthy, and found nothing material. Anything
less is a status report, not a pass. This document then leaves the repo with
the rest of the dev material.
