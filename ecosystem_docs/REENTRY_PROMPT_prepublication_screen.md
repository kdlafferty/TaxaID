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

1. `REENTRY_PROMPT_unreviewed_rows_silently_dropped.md`
2. `REENTRY_PROMPT_resident_observed_evidence_gate.md`
3. `REENTRY_PROMPT_cache_policy_P5_eviction.md`
4. `REENTRY_PROMPT_cache_policy_review.md`
5. `REENTRY_PROMPT_taxawizard_audit_and_fast_workflows.md`
6. `REENTRY_PROMPT_workflow_structure_audit.md`
7. `REENTRY_PROMPT_ptcon_18S_rerun.md`
8. `REENTRY_PROMPT_kernel_budget_pricing_and_scope.md` (decisions 1 and 3)
9. this document

`REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` is a run
checklist, not a work order. Use it as reference during steps 5 and 7.

## Must be resolved or consciously deferred first

- `REENTRY_PROMPT_unreviewed_rows_silently_dropped.md` -- observations vanish
  from the final export when the review model omits them. This is silent data
  loss and should not ship undecided.
- `REENTRY_PROMPT_resident_observed_evidence_gate.md` -- a label asserting
  evidence it does not test, with 25.7% of rows resting on under 0.01
  effective records. It feeds the published plausibility categories.
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
