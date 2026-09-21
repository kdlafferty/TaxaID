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
- **B3. The structural guards fire.** Break each deliberately and confirm it is
  caught: vignette-call checking, snippet/graph-edge export checking, the
  sampling-group kingdom guard, `cache_ok()` staleness inputs, `on_unreviewed
  = "error"`, `on_count_failure`.
- **B4. Per-package checklist passes 1-7** (memory `pre-code-review-package-
  checklist`) on every package, including `/security-review`.
- **B5. USGS release checklist** in `usgs_release_review/` with its response.
- **B6. Licensing and provenance:** CC0 throughout, `code.json` status matching
  the release type, DISCLAIMER matching provisional vs official.

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
