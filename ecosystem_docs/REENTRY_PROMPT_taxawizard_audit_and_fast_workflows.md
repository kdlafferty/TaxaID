# TaxaWizard audit, and a fast-workflow re-run

**Status: OPEN. TaxaWizard's own suite is green (641 tests, 0 failures,
2026-09-14), so this is not a firefight. It is the overdue question of whether
the package still describes the ecosystem it generates code for.**

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
