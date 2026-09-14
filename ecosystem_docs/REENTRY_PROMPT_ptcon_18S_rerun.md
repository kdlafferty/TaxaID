# Re-run PtConception 18S under the corrected sampling-group classifier

**Status: OPEN, not started. Scheduled by the user to run AFTER
`REENTRY_PROMPT_workflow_structure_audit.md` and before
`REENTRY_PROMPT_prepublication_screen.md`.**

Given its own file on 2026-09-14 because it had been tracked only as prose
inside two other documents and is the last item keeping the 2026-09-13
ecosystem review open.

## Why it has to happen

`PtConceptionWorkflow_18S_2_single_site.R` now calls
`TaxaTools::assign_sampling_group()` instead of the 97 inline lines it used to
carry. That replacement was not cosmetic. The new default scheme fixed four
real gaps that the inline copy had:

- **Diatoms** (`Bacillariophyceae`) fell into the macroinvertebrate catch-all:
  2,773 records in the real 18S occurrences. GBIF files diatoms under
  Ochrophyta, the same phylum as the kelps, so the fix had to be class-level.
- **Copepods spelled `Copepoda`**, not `Hexanauplia`, which is what live GBIF
  actually returns, so the old clause matched almost nothing.
- **`Liliopsida`** was absent from the vascular-plant clause: 114,744 records,
  5.25% of the pool, second only to the 484,072 fish. Invisible because the
  seagrass rule catches the monocot order Alismatales, so the plant clause
  looked like it handled monocots.
- **`Zygnemophyceae`** had never matched anything in the GBIF backbone; the
  accepted spelling is `Zygnematophyceae`.

After the fixes: **0 ungrouped rows in 2,185,193**, against a pool where the
catch-all had previously been silently absorbing them.

The consequence is not cosmetic either. Sampling group sets the
dark-diversity floor per stratum, and the phytoplankton stratum moves from
1,203 to roughly 3,982 records, a 3.3x change in that group's floor. That is
the stratum the 18S assay actually targets.

## What is stale until this runs

The per-group numbers for 18S are **labelled stale** in
`REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` and in
`fable_ecosystem_review_2026-09-13.md`. Both labels should be removed by
whoever completes this run, and replaced with the new numbers.

## Preconditions

- **NCBI healthy.** It was throttled on 2026-09-14. The 18S reference fetch is
  large and this workflow now runs with `ON_COUNT_FAILURE <- "error"`, so it
  will stop rather than quietly produce a degraded reference database.
- The workflow structure audit finished, per the user's chosen order.
- `SCREENS_FROM_CHECKPOINT` set deliberately, not by accident. `TRUE` serves
  both NCBI reference screens from checkpoints and avoids hours of throttled
  calls; `FALSE` runs the real screens.

## What to check when it finishes

1. **Ungrouped rows: expect zero.** Any non-zero count means the scheme needs
   another clause, and the kingdom guard should have routed it to `NA` rather
   than into a stratum.
2. **Per-group record counts and dark-diversity floors**, against the numbers
   above. Phytoplankton is the one to watch.
3. **The residual protist tail.** `Myzozoa`, `Conoidasida`, `Foraminifera`,
   `Radiolaria`, `Cercozoa`, `Oomycota`, `Haptophyta` and `Cryptophyta` are
   deliberately NOT named in the default scheme. They resolve to `NA` via the
   kingdom guard, which is the safe failure, and there are zero such records
   in the GBIF occurrence pool. They would matter on the MATCH side, where an
   18S assay is full of protists, which is exactly why
   `CaliforniaIntertidal/scope_classifier.R` keeps its own divergent
   classifier and was deliberately not migrated.
4. **`count_failures`** on the reference fetch: it is now reported as an
   attribute and named in the log. Expect empty.
5. **The unreviewed-rows check**, if that fix has landed by then:
   `sum(is.na(reviewed$llm_habitat_plausibility))` should be zero.

## Risk to remember

Every workflow to date targets fish, so the catch-all was OUT of scope and a
misclassification silently DROPPED a record. Any project that RETAINS
`macroinvertebrates` inverts this: unrecognised taxa are silently ADMITTED.
Audit the default bucket on this run rather than assuming.
