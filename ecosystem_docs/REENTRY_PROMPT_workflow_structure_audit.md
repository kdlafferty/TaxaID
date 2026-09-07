# Re-entry prompt — Production workflow structural audit

**Written 2026-09-06.** Follow-on from the `TaxaFlag::review_assignments()` rename work
(same day -- see `TaxaFlag/CLAUDE.md`'s and `TaxaID/CLAUDE.md`'s top session notes). The
user asked, after that rename sweep turned up one missed file (GreatLakes) and a handful of
heading/numbering inconsistencies: "I think we can learn a lot by outlining these
workflows... having the ability to refer these empirical workflows back to a common
workflow template is going to potentially be helpful for TaxaWizard AND being sure that the
code is being applied similarly to our various data sets." Four small, comment/heading-only
fixes were made the same session (below); this doc scopes the much bigger ask: outline
every real production workflow, compare structure, and use the result to strengthen both
the human-facing templates and TaxaWizard's machine-facing graph.

## Why this matters

These are the ecosystem's only real, currently-running end-to-end pipelines. Everything
else in this monorepo (9 packages, ~60 statistical components) exists to serve them, but
none of the workflow scripts themselves are under version control (confirmed: `git status`
in `~/My Drive/Rscripts/eDNA/` and `~/My Drive/Stats and Data/GreatLakes data/` -- neither
is a git repo), and each has been patched ad hoc, in place, across dozens of sessions
spanning many months. TaxaID/CLAUDE.md's own multi-hundred-entry session log is effectively
the only audit trail these files have. That makes them exactly the kind of asset where
drift accumulates invisibly: a fix applied to one site during a live-debugging session
doesn't automatically propagate to its siblings (this has already happened at least twice
this project -- see `[[project_workflow_propagation_list]]` and the Session 153
"template-alignment pass" in `TaxaID/CLAUDE.md`), and nobody has looked at all of them
side by side in a long time.

The user's ask has three distinct payoffs, worth keeping separate when deciding what to
build:
1. **Correctness**: outlining every workflow's real structure will surface missing steps,
   silently-reordered steps, a step split into two ad hoc pieces, or two steps quietly
   compressed into one -- exactly the shape of bug the `lab_contaminant_risk` finding below
   already demonstrates (a rename propagated to some files and not others, silently).
2. **A living reference for humans**: a genuinely current, canonical template (one, not two
   half-maintained ones) that a new site workflow can be built from with confidence it
   reflects the ecosystem's actual current conventions.
3. **A machine-checkable reference for TaxaWizard**: `TaxaWizard/inst/graph/
   workflow_graph.json` already encodes a formal node/edge graph of valid pipelines, but
   it's synced by hand against package `NAMESPACE`s (see
   `[[project_taxawizard_metadata_drift]]`), never against what the *real* workflows
   actually do end to end. An outline of every real workflow is the missing piece that
   would let a future audit check the graph against ground truth, not just against function
   signatures in isolation.

Don't conflate these three into one deliverable. The most likely genuinely useful outcome
is (1) as a byproduct of doing the outlining exercise carefully, (2) as a concrete document
this doc's own "How to do this" section produces, and (3) as a longer-term possibility to
scope separately once (1)/(2) exist -- attempting to wire the outline directly into
`workflow_graph.json` before the outline itself is trusted risks corrupting a working,
already-audited graph on the strength of an unverified new artifact.

## What's already been done (2026-09-06, same session)

- **The real 8th file caught up on the `review_assignments()` rename.**
  `GreatLakes2023_ConsensusWorkflow.R` (at `~/My Drive/Stats and Data/GreatLakes data/`,
  outside `eDNA/`) had been missed by the original 7-file sweep because that sweep was
  scoped to the `eDNA/` tree -- the exact "lives outside eDNA/" trap
  `[[project_greatlakes_workflow_debug_notes]]` already warns about. Backed up as
  `.bak_pre_llm_column_rename`, fixed identically to the other 7, parses cleanly.
- **Both real on-disk `review_assignments()` caches pruned.** `GreatLakes2023BurnsHarbor_
  review_assignments_cache` (72 entries) and `PtCon18SSchulte_review_assignments_cache`
  (1,731 entries) -- the only two sites that had actually run with `cache_dir` enabled
  since it shipped 2026-09-04 -- cleared via `TaxaFlag::taxaflag_clear_cache()`. Every
  entry was already orphaned by the rename (the cache key hashes all of `taxa_info`'s
  columns, and the rename added two new ones), so nothing live was discarded.
- **Three trivial, comment/heading-only fixes**, each backed up as
  `.bak_pre_section_heading_cleanup`, each verified to still `parse()` cleanly:
  - `PtConceptionWorkflow_12S_single_site.R`, `PtConceptionWorkflow_12S_multi_site.R`,
    `GreatLakes2023_ConsensusWorkflow.R` each gained an explicit
    `# 10.  FILTER + OUTPUT` banner + `message("\n--- Step 10: Final filtered output ---")`
    right after their `review_assignments()` step's `.save(reviewed, ...)` call, matching
    the convention `PtConceptionWorkflow_18S_2_single_site.R` and both Mugu workflows
    already use. Previously these three folded the identical filter-and-write logic into
    an unlabeled tail alongside the session-metadata/report-assembly code.
- **Two hypotheses raised earlier the same session were investigated and found NOT to be
  real** (recorded here so nobody re-flags them):
  - GreatLakes' `# 6.  MATCH STANDARDISATION (TaxaMatch)` heading looked mismatched
    against its actual content (`message("\n--- Step 6: Joining contaminant flags for
    provenance ---")`), but the step's own inline comment already explains this correctly
    -- standardisation genuinely happened at Step 1 for this dataset, and Step 6 is a
    deliberately-thin provenance join, not drift. Left untouched, per
    `[[feedback_verify_purpose_before_flagging]]`.
  - Several apparently-"unlabeled" `# ===` dividers (GreatLakes, PtCon 12S multi-site)
    turned out to be real, sensibly-titled sub-sections (`1.5`, `2.5`, `8j`, `8k`) that a
    too-strict header regex (`^# [0-9]+\.\{0,1\}\s+[A-Z]`, which requires whitespace right
    after an optional single `.`) simply failed to match during the initial survey. Not
    orphaned markers. If you re-run a structural grep for this work, use a regex that
    tolerates a decimal or lettered sub-number (e.g. `^# [0-9]+[a-z0-9.]*\s`).

## Two real findings, deliberately NOT fixed here

Both are more than cosmetic (they touch actual filter logic / actual missing structure),
so they were left for an explicit decision rather than folded into the "trivial" pass:

1. **A stale, pre-rename column reference that would error if run today.** Both
   `inst/TaxaID_Workflow_Template_TEST.R` and `PtConceptionWorkflow_12S_multi_site.R`
   still filter on the literal column name `lab_contaminant_risk`:
   ```r
   # TaxaID_Workflow_Template_TEST.R
   contaminant_ids <- contaminant_flags%>%filter(lab_contaminant_risk=="high") |> ...
   # PtConceptionWorkflow_12S_multi_site.R (inside the Step 10 filter chain fixed above)
   dplyr::filter(lab_contaminant_risk    != "high") |>
   ```
   `TaxaFlag::flag_contaminant()` stopped emitting `{contaminant_type}_risk`-style columns
   on **2026-07-24**, replaced by the unified `validity_flag`/`observation_validity` schema
   (see `TaxaID/CLAUDE.md`'s Recent Breaking Changes table, same date). Every OTHER
   production workflow's equivalent filter already reads
   `validity_flag != "invalid_lab_contaminant"` (confirmed directly in
   `PtConceptionWorkflow_12S_single_site.R`, `_18S_2_single_site.R`, both Mugu workflows,
   and GreatLakes -- all five already correct). Run as written today, both remaining
   `lab_contaminant_risk` references would throw `object 'lab_contaminant_risk' not found`
   (`dplyr::filter()` on a genuinely absent column errors, it does not silently return
   FALSE) rather than misbehave quietly -- so this is a **latent break waiting for the next
   real run of either file**, not an active bug (nobody's hit it yet, or it would already be
   fixed). The mechanical fix is a one-line change per file, identical in shape to the
   other five: `lab_contaminant_risk != "high"` → `validity_flag != "invalid_lab_
   contaminant"`. Left undone because it touches real filter logic, not a comment/heading,
   and the user's own scoping message drew the line there.

2. **`inst/TaxaID_Workflow_Template_TEST.R` may be a stale/abandoned draft**, not the
   template actually in active use. Concretely, compared against
   `PtConception/TaxaID_eDNA_Workflow_Template.R` (which the 3 PtConception production
   scripts were clearly built from -- shares its exact Section 0-10 numbering, its
   `message("\n--- Step N: ...")` convention, and its Section 2.5 spatial-grouping design):
   - The generic template has **no explicit "1. LOAD INPUT DATA" section at all** -- it
     jumps straight from `# 0.  CONFIGURATION` to `# 2.  CONTAMINANT DETECTION`.
   - It has **zero `message("\n--- Step N: ...")` console announcements anywhere** in 1,345
     lines, despite every real production workflow (and the PtCon template) having one per
     section.
   - It's the only one of the two templates never mentioned in `TaxaID/CLAUDE.md`'s
     multi-hundred-entry session log past the Session 137-153 era (the PtCon template isn't
     mentioned by that exact filename either, but its structure is clearly what those
     sessions' "template-alignment pass" produced and iterated on).

   This raises a real question worth an explicit decision, not an assumption: is
   `TaxaID_Workflow_Template_TEST.R` meant to be brought up to date to match the PtCon
   template's now-more-complete structure, or should the PtCon template simply become the
   documented canonical one (with the generic one archived or pointed at it)? Don't decide
   this unilaterally -- ask.

## The file inventory (as surveyed 2026-09-06)

| File | Location | Lines | Numbering family | Notes |
|---|---|---|---|---|
| `TaxaID_Workflow_Template_TEST.R` | `TaxaID/inst/` | 1,345 | Generic, 8 labeled sections (0, 2-8; no explicit "1") | Likely stale -- see finding 2 above |
| `TaxaID_eDNA_Workflow_Template.R` | `eDNA/PtConception/` | 1,333 | 0-10 (single-marker) | The template the 3 PtCon scripts below were actually built from |
| `PtConceptionWorkflow_12S_single_site.R` | `eDNA/PtConception/` | 2,150 (+6 this session) | 0-10 | |
| `PtConceptionWorkflow_18S_2_single_site.R` | `eDNA/PtConception/` | 2,340 | 0-10, but **no numbered Section 6** (jumps 5→7) -- not yet explained, worth checking | |
| `PtConceptionWorkflow_12S_multi_site.R` | `eDNA/PtConception/` | 1,771 (+6 this session) | 0-10 | Has the `lab_contaminant_risk` finding above |
| `ReviewedESVs.R` | `eDNA/PtConception/` | 21 | N/A -- not a workflow | A tiny post-hoc taxon-filter script, not part of the structural audit |
| `MuguFishWorkflow.R` | `eDNA/SepulvedaMugu/` | 2,100 | 0-11 (multi-marker) | Loads pre-built per-marker match objects (its own Step 1) |
| `MuguWilderFishWorkflow.R` | `eDNA/SepulvedaMugu/` | 1,684 | 0-12 (multi-marker) | One extra step vs. MuguFishWorkflow: builds per-marker match objects itself (its own Step 6) |
| `GreatLakes2023_ConsensusWorkflow.R` | `Stats and Data/GreatLakes data/` | 2,039 (+6 this session) | 0-10 (single-marker) | Lives outside `eDNA/` -- always grep both locations |

Two legitimate numbering families, not one universal scheme -- see `TaxaID/CLAUDE.md`'s
matching entry for why (single-marker vs. multi-marker pipelines genuinely do a different
number of things; "Step 9" means TaxaFlag review in one family and cross-marker prior
update in the other).

## How to do the outlining (proposed, not yet started)

1. **Per file, produce a structural outline table**, not a rewrite: `Section # | Title |
   Real functions called (package::function) | Key objects saved via .save()/saveRDS() |
   Anything that deviates from its own numbering family's norm`. This is read-only work --
   grep for `^# [0-9]`, `message("\n--- Step`, `\.save\(`, and the main `package::function(`
   call sites per section; only read full sections directly where the grep alone doesn't
   settle what a section does.
2. **Cross-reference each outline against its own family's peers** (PtCon 12S/18S_2/
   GreatLakes against each other; the two Mugu workflows against each other) to find:
   missing steps, reordered steps, a step split in two in one file but not its sibling, two
   steps compressed into one. The 18S_2 missing-Section-6 case above is the obvious first
   thing to resolve this way.
3. **Cross-reference the single-marker family's outline against
   `TaxaID_eDNA_Workflow_Template.R`** (the template that family was actually built from) to
   find where a production script has drifted from its own template, or where the template
   itself has fallen behind something all three production scripts independently added
   (spatial grouping, review caching, etc. all shipped after the template was last
   touched -- confirm whether it's current).
4. **Only after 1-3 exist**, decide with the user: (a) does `TaxaID_Workflow_Template_
   TEST.R` get retired/updated/merged with the PtCon template; (b) is there appetite for a
   Mugu-family template (none exists today, unlike the single-marker family); (c) does any
   of this feed into `TaxaWizard/inst/graph/workflow_graph.json` as new edges/nodes, or
   stay purely documentation. Don't build (c) speculatively -- the graph is currently
   correct and hand-audited; wiring in something unverified risks the opposite of the goal.
5. **Fix the two real findings above** (the `lab_contaminant_risk` latent break, the
   template staleness question) as part of this pass, not before it -- they're exactly the
   kind of thing the outlining exercise should catch systematically rather than one at a
   time.

## Safety notes (read before touching anything)

- **None of these 9 files are under git.** `cp file.R file.R.bak_<description>` before any
  edit, every time, no exceptions -- this project's own established convention for exactly
  this reason. Never batch multiple files' backups under one generic suffix if the edits
  differ in kind (this session used `.bak_pre_llm_column_rename` for the rename and a
  separate `.bak_pre_section_heading_cleanup` for the heading work, so each backup names
  what it precedes).
- **Verify with `Rscript -e "parse('file.R')"` after every edit**, not just at the end of a
  batch -- cheap, catches a broken edit immediately rather than after several more changes
  have piled on top of it.
- **A full renumbering or terminology rewrite across these files is explicitly out of
  scope** unless separately agreed with the user after the outline exists -- these are
  live, unversioned production scripts with real checkpointed `.rds` state; a mass edit
  that looks safe in a diff can still silently break a downstream `readRDS()` call keyed on
  an exact variable/column name introduced or renamed along the way.
- **This whole document describes an audit, not a mandate.** The user's own framing was
  "let's see what we can do" -- present findings and a scoped proposal before executing
  anything beyond the outline itself.
