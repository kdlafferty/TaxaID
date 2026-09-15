# TaxaWizard audit, and a fast-workflow re-run

**Status: PARTS 1-4 DONE 2026-09-15. Part 5 partly covered. Part 3 measured and OPEN (the
snippets, not the metadata). Part 5 partly covered. TaxaWizard 643 tests, 0
failures; check() 0/0/0 (plus the usual timestamp note).**

## 2026-09-15 progress

**Part 2 -- the decision, made: metadata must cover what real workflows
CALL.** Not "every export" and not a hand-curated list. The criterion is
computed from the workflow corpus, so it cannot drift the way a curated list
did.

That reframed the size of the problem. Of the 105 missing exports, only **45
were called by any real workflow**; the other 60 are never called anywhere
(prompt builders, response parsers, provider-registry internals) and are out
legitimately. The metadata was also **not wrong** -- 0 stale entries, nothing
naming a function that does not exist. The drift was purely one-directional.

**Part 1 -- DONE. 50 entries added, gap now 0.** Generated from each
function's own installed `.Rd` (title -> description, `\arguments` -> input
descriptions, formals -> required/default), so the text is the real
documentation rather than invented prose. All 12 cache-management functions
are now present, along with core pipeline steps that had been missing:
`calibrate_query_noise`, `restore_suppressed_candidates`,
`expand_unreferenced_hypotheses`, `get_gbif_occurrences`,
`apply_coverage_constraints`, `unreferenced_candidates`, `assign_scores`, and
every `report_*`.

Trap worth recording: evaluating a default like
`tools::R_user_dir("TaxaFlag", "cache")` bakes THIS machine's absolute path
into shipped metadata. Literal defaults are recorded as `default`; anything
else as `default_expr`, the deparsed call. The files were checked for
`/Users/` afterwards -- clean.

**The guard: `TaxaWizard/tests/testthat/test-metadata-covers-workflow-functions.R`.**
It scans the in-repo corpus and asserts every ecosystem function called there
has a metadata entry. Verified to actually FAIL (not skip) when an entry is
removed -- checked by deleting `calibrate_query_noise` and confirming
1 failure, 0 skips. It covers the in-repo corpus only, because the production
site workflows live outside this repository and cannot be a test dependency;
the metadata deliberately covers a superset.

The pre-existing structural guard tests the OTHER direction (every function
NAMED in a snippet must be a real export), which is why this drift was
invisible: nothing could see an omission.

**Part 4 -- DONE, all five fast workflows green** (NCBI healthy again):

```
run_fast_smoketest.R             OK   6.0s
run_greatlakes_fast_smoketest.R  OK   5.0s
run_mugu_fast_smoketest.R        OK   0.1s
run_ptcon18s_fast_smoketest.R    OK  36.1s
run_review_fixes_fast_check.R    OK  63.2s
```

Mugu's 0.1s is real work, not a skip: 75 observations, the *Fundulus
lima/parvipinnis* edge case, and `irreducible_consensus` 69 TRUE / 6 FALSE --
the 2026-09-04 order-invariance bug would have made every row FALSE.

NOTE for the next reader: these scripts resolve paths relative to the PROJECT
ROOT (`file.path("diagnostics", "fast_workflows", ...)`). Running them with
the working directory set to their own folder fails instantly on
`file.exists(fixture_path)` and looks like missing fixtures. The fixtures are
present and committed.

**Part 3 -- MEASURED, and the gap is in the SNIPPETS, not the metadata.**
Metadata coverage no longer implies generated workflows use these
conventions. Of 30 snippets:

| convention | snippets carrying it |
|---|---|
| `cache_dir` | 3 of 30 |
| `on_count_failure` / `count_attempts` | **0** |
| `cache_ok()` staleness gate | **0** |
| `options(cli.progress_show_after = Inf)` | **0** |

That was fixed the same day. Generated workflows now carry, with the reason
stated inline in each case so the next reader knows why it is there:

| change | where |
|---|---|
| `on_count_failure = "error"` + `count_failures` check | `taxa_to_refs.R`, `taxa_to_site_refs.R` |
| `on_unreviewed = "error"` + residue check | `consensus_to_reviewed.R` |
| `cache_dir` on the NCBI reference fetch and coverage audit | `taxa_to_refs.R`, `taxa_to_site_refs.R`, `taxa_refs_to_gaps.R` |
| `cache_dir` on the GBIF fetch and outlier check | `taxa_to_occ.R`, `taxa_to_occ_checked.R` |
| GBIF `limit` truncation warning | both GBIF snippets |
| `options(cli.progress_show_after = Inf)` | the generated script PREAMBLE (`R/output.R`), not a snippet |

Two of these are guards against incidents this ecosystem has already suffered:
seven genera losing their entire reference representation to transient NCBI
count failures, and 20 observations vanishing from a species list because the
review model omitted them. A generated workflow previously reproduced both.

The GBIF `limit` warning is a comment, not a parameter change, because
`fetch_gbif_occurrences()` has no `on_cap` guard -- only
`get_gbif_occurrences()` does, and that routes to the download API above 50
keys, which needs a GBIF account a generated demo may not have. The comment
carries the measured evidence (45 of 231 Mugu taxa and 110 of 666 PtCon taxa
at the cap, every capped taxon sharing an identical spatial distribution).

STILL NOT DONE from this part: `cache_ok()` staleness gates in snippets. That
needs each snippet to declare which artifacts its output derives from, which
is a per-edge design decision rather than a mechanical edit.

Verified in real generated output, not just by reading the diff: a generated
script was produced and its preamble confirmed to carry the cli line.

**Part 5 -- partly covered.** Script and app GENERATION are exercised by the
suite (it writes real app.R files during the run). A generated app has still
not been launched and clicked through.


## 1. TaxaWizard does not know about caches at all

Measured 2026-09-14 against the installed packages:

| package | exports | absent from TaxaWizard metadata |
|---|---|---|
| TaxaTools | 51 | 42 |
| TaxaFetch | 32 | 24 |
| TaxaHabitat | 17 | 7 |
| TaxaMatch | 32 | 4 |
| TaxaLikely | 33 | 22 |
| TaxaExpect | 15 | 2 |
| TaxaAssign | 16 | 2 |
| TaxaFlag | 11 | 2 |
| **total** | **207** | **105 (51%)** |

Treat 51% as an upper bound on the problem, not a defect count: the metadata
may never have been intended to cover every export. But the pattern inside it
is not ambiguous. **Every cache-management function in the ecosystem is
missing:**

- TaxaTools: `cache_ok`, `taxaid_cache_report`, `list_cache_files`,
  `report_and_clear_cache`, `taxatools_clear_cache`, `model_cache_info`
- TaxaLikely: `taxalikely_clear_cache`, `taxalikely_evict_unreachable_cache`
- TaxaFetch: `taxafetch_clear_cache`
- TaxaHabitat: `taxahabitat_clear_cache`
- TaxaFlag: `taxaflag_clear_cache`
- TaxaMatch: `migrate_reference_cache`

So a generated workflow cannot be told to pass a `cache_dir`, cannot declare
staleness inputs via `cache_ok()`, and cannot offer the user a way to report
or clear what it fills up. Given that the cache-policy review of the same week
concluded caching should be caller-driven and project-scoped, a generator that
has never heard of it will produce workflows that silently use the hidden
per-user defaults.

## 2. What to decide first

Whether TaxaWizard's metadata is meant to be **complete** (every export, kept
in sync by a test) or **curated** (only workflow-relevant functions). Today it
is neither: it is a curated set that has drifted. Answer that before adding
105 entries.

A completeness test is cheap and would stop the drift permanently, in the same
spirit as the structural guard already added 2026-09-13 that requires every
function named in a snippet or graph edge to be a real export.

## 3. Changes since TaxaWizard last looked

Worth checking each against the generator's snippets and metadata:

- `TaxaLikely::fetch_ncbi_reference_sequences(count_attempts, on_count_failure)`
  and its `count_failures` attribute.
- `TaxaTools::cache_ok()`, `taxaid_cache_report()`,
  `list_cache_files(recursive =)`.
- `TaxaTools::assign_sampling_group()` / `default_sampling_scheme()`, which
  replaced 97 inline lines in the 18S workflow.
- `TaxaLikely::taxalikely_evict_unreachable_cache()` and the recursive
  `taxalikely_clear_cache()`.
- `TaxaFetch::download_gbif_occurrences()` geometry verification.
- `options(cli.progress_show_after = Inf)` and the console-log block, now in
  all six production workflows and the template. A generated workflow that
  logs should carry both.

## 4. Re-run the fast workflows

`diagnostics/fast_workflows/` has one per real site plus
`run_review_fixes_fast_check.R` (arms A-E, ~60s). They have not been run since
the count-failure guard, the cli change, the cache-before-count work and the
propagation to all six workflows. Run them before trusting any of it.

**NCBI was throttled on 2026-09-14.** Arms that touch NCBI will be
unreliable; the reference-fetch and screen arms are the ones to watch. Prefer
the checkpoint-served paths (`SCREENS_FROM_CHECKPOINT <- TRUE`) and re-run the
NCBI arms when the throttle clears. A failure there is not evidence of a code
defect until NCBI is known healthy.

## 5. Also unverified

TaxaWizard's generated Shiny app path and the `eval(parse())` allow-list fix
from 2026-08-09 have not been exercised against the current metadata. The test
suite covers script generation; a real generated app has not been run recently.
