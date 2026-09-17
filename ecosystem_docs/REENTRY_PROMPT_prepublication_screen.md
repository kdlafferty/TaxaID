# Pre-publication screen: the one that has to pass clean

**Status: OPEN, not started. This is the closing gate, not another fix round.**

## Why this exists, in the user's words

Every pre-publication pass so far has found fixes, and each round of fixes has
led to more fixes. The point of this screen is to **end that loop**: a pass
that finds nothing material, run against a codebase nobody is still editing.

That framing changes how it should be run. The previous reviews were
*discovery* exercises and succeeded by finding things. This one succeeds by
finding nothing. If it finds something material, the honest conclusion is that
the ecosystem was not ready, and the screen is repeated after the fix, not
patched mid-flight.

## Entry conditions -- do not start until all are true

1. **No open edit sessions.** Two concurrent sessions were editing the same
   files on 2026-09-14. A screen run over a moving tree proves nothing.
2. **All three repositories clean and committed** (TaxaID, `eDNA/`,
   `GreatLakes data/`).
3. **All nine packages `devtools::check()` clean** and reinstalled from the
   committed state, with build timestamps verified, not assumed.
4. **NCBI healthy.** It was throttled on 2026-09-14. Several checks cannot be
   distinguished from real defects while it is not.
5. **The open items below are closed or explicitly deferred in writing.**

## Agreed running order (set by the user, 2026-09-14)

Work these in order. Each one's output can change the next, which is why the
order is not arbitrary.

1. ~~`REENTRY_PROMPT_unreviewed_rows_silently_dropped.md`~~ -- DONE 2026-09-14
   (commits 72c9d2b / 95d9bee). The doc is retired; see TaxaFlag's
   `@section Unreviewed rows`. Re-run outcome: 20 unreviewed rows -> 0, but
   the export is unchanged at 224 OTUs, because the recovered units are now
   rated geographically unlikely by the skepticism gate despite the
   reviewer's own prose calling them Point Conception natives. That
   calibration question is open and is NOT tracked elsewhere.
2. ~~`REENTRY_PROMPT_resident_observed_evidence_gate.md`~~ -- DONE 2026-09-15
   (commits c493117 / 42bb24e / cae94e9 / c609398 / ba422f4). Doc retired.
   Decision: rename `resident_observed` -> `kernel_estimated` plus an explicit
   evidence knob (`posterior_consensus(min_effective_records=)`, default 0);
   NO gate, because effective_records is continuous over ~10 orders of
   magnitude with no valley to cut at. The group-prior rank-coverage defect
   was folded in (rank_cols now reaches order/class).
   VALIDATED on both sites:
   - PtCon 12S: 0 unreviewed rows; the Perciformes unit went
     unprecedented -> not_modeled, its review verdict unlikely -> likely, and
     3 of the 4 previously-lost units reached the export. The 4th is blocked
     by the export's own `!is.na(consensus_taxon)` filter, not by the gate.
     Species count 159 -> 154 is NARROWING, not loss: all 11 Chinook rows went
     from a 3-way `mykiss/nerka/tshawytscha` set to 8 rows calling
     `O. tshawytscha` outright. Remaining churn is Sebastes re-slicing, which
     the user confirms is honest -- Sebastes are genuinely hard to discern.
     Regenerated reports corroborate independently:
     llm_geographic_plausibility flags 306 -> 261.
   - GreatLakes: species-level precision 840/(840+123) = 0.8723 against the
     0.872 benchmark, species intersection 42/61 against 42/61. No regression.
   RESIDUAL -- now ATTRIBUTED (2026-09-15), it was DATA, not the code.
   GreatLakes moved species-resolved 694 -> 686 and unexpected 1 -> 18. A
   two-arm test settled it:
     run 1 vs a second identical run   0 of 885 rows differ  (deterministic)
     run 1 vs the 2026-09-11 baseline  8 of 885 rows differ
   The pipeline is reproducible, so the 8 rows are the refreshed data. Cause
   traced precisely: the fastpath re-fetched regional-proximity evidence
   (the zero_bbox_taxa set had changed, so the cache key missed), which moved
   theta on 346 resident_undetected rows and ONLY those -- the priors were
   otherwise structurally identical (same 483 rows, 467 taxa, branch counts
   90/388/5, transport unchanged). That dragged
   median(taxaexpect_priors$theta_mean) from 1.72e-07 to 1.48e-08, an 11.7x
   shift in the Axis-1 species threshold, reclassifying 17 rows.
   The code is exonerated independently too: GreatLakes has zero order-rank
   consensus rows, and the genus/family thresholds are computed with explicit
   per-rank filters, so adding order/class rows to group_priors cannot touch
   them.
   TWO FINDINGS KEPT FROM THIS, both publication-relevant:
   (a) The expected/unexpected boundary FLOATS with the data, because the
       workflows derive it from the table being classified. It is a
       within-run relative judgement, so `unexpected` counts are not
       comparable across runs or sites unless the threshold is reported
       alongside. Now documented in add_posthoc_assessment()'s
       expected_theta_threshold roxygen.
   (b) The prior_branch legacy-string tolerance earned itself within a day:
       run 1's priors still read "resident_observed" because the kernel fit
       came from an .fp_cache written before the rename. Without the
       tolerance that cached fit would have dropped silently out of every
       downstream filter.
3. ~~`REENTRY_PROMPT_cache_policy_P5_eviction.md`~~ -- DONE 2026-09-15
   (commits 2d31cca / 05add25). Doc RETIRED 2026-09-15 once both sweeps had run and the
   fasta/ item was verified; its two traps moved to CLAUDE.md's Known R
   Footguns. Both sweeps run, user-approved:
   **168.1 MB -> 45.0 MB**, 7,588 -> 6,002 files. TaxaFetch lost exactly its
   two orphans (the 127,733,417-byte truncated download quarantined
   2026-09-05, and a 0-byte zip); both surviving zips still have metadata.
   TaxaLikely evicted 1,584 of 3,517 meta files, 1,933 live, `fasta/`
   untouched. The `fasta/` versioned-key item was live-verified once NCBI
   recovered: a cold fetch wrote 4 of 4 versioned filenames against 0 of
   4,061 in the pre-fix cache. Legacy notes left alone by decision.
4. ~~`REENTRY_PROMPT_cache_policy_review.md`~~ -- CLOSED 2026-09-15, doc
   retired. **Superseded by the review it commissioned**
   (`CACHE_POLICY_REVIEW_2026_09_14.md`), which assessed its candidate scope
   and deliberately narrowed it. Its "Status: OPEN, nothing implemented" was
   stale. Reconciled item by item:
   - one documented policy -> BUILT (that 768-line review)
   - `cache_dir = NULL` as uniform default -> **DECIDED AGAINST**: 11
     functions would change behaviour at once mid-project, and the workflows
     already pass explicit dirs nearly everywhere. P3 fixed the two genuine
     offenders instead.
   - mandatory `inputs=` on every cache -> **DECIDED AGAINST as a blanket**:
     the per-taxon caches derive from NCBI, not a local artifact, so they
     have no `inputs` to declare -- their staleness axis is time, i.e. a TTL.
     Applied where it does belong; 4 workflow files now use `cache_ok()`.
   - ecosystem report/clear -> `TaxaTools::taxaid_cache_report()` BUILT and
     exported (with `warn_gb`); an ecosystem-level CLEAR deliberately NOT
     built, because the five caches do not share one shape and TaxaMatch's is
     row-level and TTL'd.
   - size budget -> BUILT (`warn_gb`).
   - re-examine the 2026-07-13 cache removal -> DONE. P1 reordered the fetch
     so the cache is consulted BEFORE the count query (the actual cause of
     the incident); the single-site `reference_df` read stays unbuilt on
     measurement -- warm Step 7a is 3 seconds.
   The three questions it posed are answered in that review's Parts 9-11.
5. ~~`REENTRY_PROMPT_taxawizard_audit_and_fast_workflows.md`~~ -- DONE
   2026-09-15 (commits fadf4c6 / 0b333b3 / fdc28ab). Doc retired. Metadata now
   covers every function a real workflow calls, guarded by a computed test
   that was verified to fail rather than skip; generated workflows carry
   on_count_failure, on_unreviewed, cache_dir and cli suppression; all five
   fast workflows green; a generated Shiny app was launched (HTTP 200) and its
   eval(parse()) allow-list attacked with 6 hostile inputs, all rejected. The
   one residual is listed under "Carried forward from retired prompts".
6. `REENTRY_PROMPT_workflow_structure_audit.md`
7. `REENTRY_PROMPT_ptcon_18S_rerun.md`
8. `REENTRY_PROMPT_kernel_budget_pricing_and_scope.md` (decisions 1 and 3)
9. this document

`REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` is a run
checklist, not a work order. Use it as reference during steps 5 and 7.

## Must be resolved or consciously deferred first

- `REENTRY_PROMPT_taxawizard_audit_and_fast_workflows.md` -- 51% metadata
  drift and no knowledge of caching.
- `REENTRY_PROMPT_cache_policy_review.md` and
  `CACHE_POLICY_REVIEW_2026_09_14.md` -- whatever remains unimplemented.
- `REENTRY_PROMPT_ptcon_18S_rerun.md` -- PtConception 18S has never been
  re-run under the corrected sampling-group classifier. Its per-group numbers
  are labelled stale in this directory and in
  `fable_ecosystem_review_2026-09-13.md`. Publishing stale numbers is the
  specific risk.
- **pkgdown**: no `_pkgdown.yml` exists for any package, and the manuscript
  plan requires a working site per package before submission.

## Carried forward from retired prompts (2026-09-15)

The TaxaWizard audit and the cache-policy P5 prompts were completed and
deleted. One genuinely open item survives them, small but real:

- **`cache_ok()` staleness gates are not in TaxaWizard's snippets.** Generated
  workflows now carry `on_count_failure`, `on_unreviewed`, `cache_dir` and the
  cli suppression (commit 0b333b3), but no staleness gate. Adding one needs
  each graph edge to declare which artifacts its output derives from -- a
  per-edge design decision, not a mechanical edit. Decide whether a generated
  workflow should ship with staleness detection before release, or whether
  that stays a hand-written-workflow feature.

Everything else from those two prompts is closed. Their traps worth carrying
are now in `TaxaID/CLAUDE.md`'s Known R Footguns (the
`.ref_cache_grammar()`/key lockstep rule was already there; the stolen
`@export` and the `workflow_app()` `readline()` hazards were added when they
were retired).

## Baseline as of 2026-09-15 (carry into the screen)

**All nine packages green: 7,394 tests, 0 failures; `check()` clean on every
one** (bar the usual unverifiable-timestamp NOTE). That includes TaxaFetch,
which had carried 2 failures since 2026-08-08 labelled "pre-existing
CoordinateCleaner environment failures, unrelated". **They were neither.**
`cc_zero(buffer=)` changed from degrees to metres in CoordinateCleaner 3.x
while its default stayed `0.5`, so `filter_gbif_quality()`'s null-island check
had silently become a no-op. Fixed; 812/0. No result changed (0 of 3.75 M real
GBIF rows are within 55 km of (0,0)), so nothing needed re-running.

Carry the lesson into the screen, not just the fix: **a test failing for a
month is evidence, not furniture.** Three package CLAUDE.mds and a reentry
prompt repeated the "environmental" label, and one of them instructed readers
not to investigate. When a dependency is involved, call the dependency
directly with the test's own fixture before accepting that explanation.

**pkgdown is OUT of scope** for this release by user decision (2026-09-15) and
has been removed from the running order. The "Must be resolved" bullet below
still lists it; treat that as superseded.

**Two properties to REPORT rather than fix**, both measured this session and
both liable to confuse a reviewer comparing tables:

- The Axis-1 `expected`/`unexpected` boundary is
  `median(taxaexpect_priors$theta_mean)`, computed from the very table being
  classified, so it FLOATS with the data. At GreatLakes, refreshing only the
  evidence rows moved it 11.7x and took `unexpected` from 1 to 18 with no code
  change. An `unexpected` count is not comparable across runs or sites unless
  the threshold is reported with it.
- `prior_branch` says which GENERATOR produced a prior row, never how much
  evidence stands behind it. Within the one kernel branch, `effective_records`
  spans ~10 orders of magnitude: 44.9% of PtCon 12S rows, 64.9% of PtCon 18S
  and 18.9% of GreatLakes sit under one Kish effective record. No gate is
  applied by default.

**The pipeline is deterministic.** Two full GreatLakes runs on identical
inputs produced byte-identical consensus rows (0 of 885 differing), despite
1,000-draw Monte Carlo in `compute_posterior()` and
`update_prior_from_consensus()` and no `set.seed()` anywhere -- the consensus
reads `posterior_point_est`, the deterministic estimate. Worth stating
explicitly in a methods section; a reader will otherwise assume otherwise.

## What the screen itself should cover

1. **Reproducibility from a clean checkout.** Clone to a fresh directory,
   install in dependency order, run every package's tests. Nothing may depend
   on state that only exists on the author's machine.
2. **Every number in the manuscript and in the shipped documents traced to a
   run that still reproduces.** The recurring failure in this project is a
   figure that was true when written and silently stale afterwards.
3. **The four structural guards still fire**: vignette-call checking, snippet
   and graph-edge export checking, the sampling-group kingdom guard, and the
   cache staleness inputs. Break one deliberately and confirm it is caught.
4. **A scan for claims rather than code.** This project has repeatedly found
   comments and roxygen asserting behaviour the code does not have, including
   one "can never again silently serve stale reference data" comment that was
   false when written. Grep for absolute claims and check each.
5. **The USGS release checklist** in `usgs_release_review/`, whose remaining
   open items are listed in that folder's README.
6. **Licensing and provenance**: CC0 throughout, `code.json` status matching
   the intended release type, DISCLAIMER matching provisional versus official.

## Method note

Run the discovery passes as subagents on a cheaper model and reserve the
expensive model for adjudication; that is what the 2026-09-13 review did after
a spend limit killed seven agents mid-flight. And verify file lists by opening
files, not from grep hit counts, which produced a wrong "five files" claim in
that same review.

## Definition of done

A written statement that the screen was run against a named commit in each of
the three repositories, with NCBI healthy, and found nothing material. Anything
less is a status report, not a pass.
