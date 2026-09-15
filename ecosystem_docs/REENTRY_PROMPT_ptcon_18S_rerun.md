# Re-run PtConception 18S under the corrected sampling-group classifier

**Status: OPEN, not started. READY TO RUN as of 2026-09-15 -- see "Prep" below.**

Originally scheduled after `REENTRY_PROMPT_workflow_structure_audit.md`; the
user has chosen to run it earlier, in its own session, because it needs a
multi-hour block. That is safe: the structure audit is a
comparison-and-documentation pass whose previous round produced only
comment/heading changes, so it is not expected to alter 18S output. If it
ever does propagate a substantive fix to this workflow, re-run then.

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

## Prep (verified 2026-09-15, before you start)

**1. Nothing needs installing. Do not install anything.**
All nine packages are installed and current -- no package's source is newer
than its build:

```
TaxaTools   2026-09-14 21:16   TaxaExpect  2026-09-15 00:11
TaxaFetch   2026-09-15 10:50   TaxaAssign  2026-09-15 00:11
TaxaHabitat 2026-09-14 21:16   TaxaFlag    2026-09-14 23:08
TaxaMatch   2026-09-14 21:16   TaxaWizard  2026-09-15 11:48
TaxaLikely  2026-09-14 21:16
```

**2. Start from a RESTARTED R session, and do not install during the run.**
This is not boilerplate. On 2026-09-14 a package was reinstalled while a
workflow session had it loaded; the session had the old `.rdb`
memory-mapped, the install replaced the file underneath it, and the run died
mid-Step-5 with

```
lazy-load database '.../TaxaExpect/R/TaxaExpect.rdb' is corrupt
```

Nothing was actually broken on disk -- a restart alone fixed it -- but the
run was lost. So: `.rs.restartR()`, then confirm what you are about to run
against:

```r
library(TaxaTools); library(TaxaFetch); library(TaxaHabitat)
library(TaxaMatch); library(TaxaLikely); library(TaxaExpect)
library(TaxaAssign); library(TaxaFlag)
packageDescription("TaxaExpect")$Built   # expect 2026-09-15 00:11 or later
packageDescription("TaxaFlag")$Built     # expect 2026-09-14 23:08 or later
```

**3. NCBI is healthy** -- checked 2026-09-15, `esearch` HTTP 200 in 0.31 s.
The precondition below is satisfied. Re-check if you start much later.

**4. Decide `SCREENS_FROM_CHECKPOINT` deliberately** (see Preconditions).

**5. Expect a long run and do not interrupt it.** The comparable PtCon 12S
full run took ~1 h 53 m cold. 18S is larger.

## What changed under this workflow since it last ran (2026-09-15)

The script itself was edited three times this session. All three are in the
eDNA repo's history; none should need your attention unless something fails.

- `review_assignments(..., on_unreviewed = "error")`. An LLM review can parse
  cleanly, return the right number of objects and still OMIT taxa; those rows
  get `NA` in every `llm_` column and the export filters discard `NA`. The run
  now STOPS rather than exporting a silently short species list. **If it stops
  with "N candidate set(s) have NO LLM verdict", that is this guard, not a
  crash -- re-run and it recovers, because unreviewed taxa are never cached.**
- `prior_branch` now reads `%in% c("kernel_estimated", "resident_observed",
  ...)` in three places. `TaxaExpect` renamed the branch; both names are
  accepted permanently. A bare equality would have matched ZERO rows on the
  next fresh priors run while looking fine against every cached table.
- Group priors gained ORDER and CLASS coverage. `compute_group_priors()`'s
  `rank_cols` stopped at family, so a consensus resolving at order rank found
  no group row, read `consensus_has_occurrence_record = FALSE` and was
  reported `"unprecedented"` from that gap alone. **This one CHANGES NUMBERS.**
  At PtCon 12S it recovered a 20-observation unit that the skepticism gate had
  been rating geographically "unlikely" against its own review comment.

Also relevant, though neither should change 18S output:
`filter_gbif_quality()` gained `near_zero_buffer_m` (the null-island check had
become a no-op after CoordinateCleaner changed that buffer's units from
degrees to metres) -- 0 of 3.75 M real GBIF rows at any site were affected.

## Extra things to check on THIS run

Beyond the five checks below, which all still apply:

6. **Order-rank consensus rows.** New this session. Check
   `table(consensus_final$consensus_rank)` for an `order` entry, and whether
   those rows now read `not_modeled` rather than `unprecedented`. Note
   `expected_theta_threshold` has no `"order"` entry, so an order-rank call
   correctly reports `not_modeled` -- that is honest, and it is enough to stop
   the skepticism gate firing. Adding an order threshold is a scientific
   choice nobody has made yet.
7. **`prior_branch` should read `kernel_estimated`** in freshly generated
   priors. If it still reads `resident_observed`, the kernel fit came from a
   cache written before the rename -- which is fine and expected, and is
   exactly why both names are accepted.
8. **Compare per-group numbers against a threshold, not across runs.** The
   Axis-1 `expected`/`unexpected` boundary is
   `median(taxaexpect_priors$theta_mean)`, computed from the very table being
   classified, so it FLOATS with the data. At GreatLakes, refreshing only the
   evidence rows moved that median 11.7x and took `unexpected` from 1 row to
   18 with no code change and nothing wrong. Report the threshold alongside
   any `unexpected` count.
9. **18S's branch composition is worth a look on its own.** Of its 1,521
   `resident_observed` rows measured 2026-09-14, **987 (64.9%) rested on under
   one Kish effective record** -- the highest of any site (PtCon 12S 44.9%,
   GreatLakes 18.9%). That is why the branch was renamed. No gate is applied
   by default (`posterior_consensus(min_effective_records = 0)`), so this
   changes nothing automatically, but it is the site where an evidence
   threshold would bite hardest if one is ever adopted.

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
