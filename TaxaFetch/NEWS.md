# TaxaFetch 0.1.0

## 2026-09-13

* `download_gbif_occurrences()`: a download key recorded as *pending* (see the
  2026-09-10 entry below) is no longer honoured forever once GBIF has itself
  killed, cancelled, failed, or purged it server-side -- previously every
  subsequent call died identically, and the only recovery was deleting the
  cache metadata file by hand. Two fixes: a pending record older than the new
  `pending_max_age_days` (default 30) is abandoned without polling it at all;
  and when the poll on a still-fresh pending key fails non-transiently, the
  dead record is cleared and a fresh request is submitted automatically, in
  the same call.

## 2026-09-10

* `download_gbif_occurrences()`: the download request is retried with backoff
  when GBIF answers with a transient server-side failure (new `submit_attempts`,
  `submit_wait`); non-transient errors are raised at once. When every attempt
  fails and a verified cached zip for the exact query exists (`overwrite =
  TRUE`), new `on_submit_failure = "use_cache"` (default) imports it with a
  warning and sets `attr(out, "served_from_cache_after_failure")`; `"error"`
  restores the old behaviour. Motivated by a real run dying on GBIF's
  "HTTP 503 Backend fetch failed" with an identical verified zip on disk.
* `download_gbif_occurrences()`: the fetch of the prepared file now treats a
  thrown transfer error (curl connection timeout, reset, empty reply) as the
  same transient failure as a truncated zip: retried with backoff, then the
  same verified-cache fallback. Previously a thrown curl error escaped the
  retry loop entirely.
* `download_gbif_occurrences()`: the status poll (`occ_download_wait()`) is
  retried the same way; and when GBIF has issued a key but the poll or fetch
  still fails with no cache to fall back on, the key is recorded as *pending*
  in the cache metadata so the next call re-fetches the prepared download
  instead of submitting a new request.

## Polishing Phase (Sessions 57-59)

* Removed dead code: `combine_occurrence_sources()` (superseded by
  `rename_cols()` + `stack_occurrences()`).
* Deleted stale workflow files: `TaxaFetch_workflow copy.R`,
  `migrate_prompt_api.R`, `habitat_scheme_workflow.R`.
* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Fixed LaTeX escape in `search_literature()` documentation.
* Added vignette: data-acquisition.Rmd.
