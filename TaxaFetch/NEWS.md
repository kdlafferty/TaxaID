# TaxaFetch 0.1.0

## 2026-09-10

* `download_gbif_occurrences()`: the download request is retried with backoff
  when GBIF answers with a transient server-side failure (new `submit_attempts`,
  `submit_wait`); non-transient errors are raised at once. When every attempt
  fails and a verified cached zip for the exact query exists (`overwrite =
  TRUE`), new `on_submit_failure = "use_cache"` (default) imports it with a
  warning and sets `attr(out, "served_from_cache_after_failure")`; `"error"`
  restores the old behaviour. Motivated by a real run dying on GBIF's
  "HTTP 503 Backend fetch failed" with an identical verified zip on disk.

## Polishing Phase (Sessions 57-59)

* Removed dead code: `combine_occurrence_sources()` (superseded by
  `rename_cols()` + `stack_occurrences()`).
* Deleted stale workflow files: `TaxaFetch_workflow copy.R`,
  `migrate_prompt_api.R`, `habitat_scheme_workflow.R`.
* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Fixed LaTeX escape in `search_literature()` documentation.
* Added vignette: data-acquisition.Rmd.
