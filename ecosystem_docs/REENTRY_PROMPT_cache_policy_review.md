# Cache policy review (opened 2026-09-14)

**Status: OPEN, nothing implemented. Deliberately separated from the
2026-09-14 `fetch_ncbi_reference_sequences()` count-failure fix so that a
bug fix does not quietly become an architecture change.**

## Why this exists

Raised by the user on 2026-09-14, in these words: a worry that automatic
caching "interferes with their ability to analyze data OR fills up their hard
drive", or conversely that "the lack of caching means each workflow takes
hours to run redundant processing", and that the ecosystem has been handling
caching "piecemeal".

The trigger was a real incident, though the incident turned out NOT to be
caused by caching. Seven NCBI count queries failed transiently on the
PtConception 12S run and silently cost seven genera their entire reference
representation. Investigating it surfaced the pattern below, which is worth
addressing on its own terms rather than in reaction to that bug.

## The pattern worth fixing: this ecosystem keeps swinging between extremes

Two real incidents, opposite directions, same underlying cause.

- **2026-07-13, cache too sticky.** A cached `reference_df` went stale
  relative to `match_obj` after an upstream contaminant-filtering fix. It had
  zero *Girella* rows, so `restore_suppressed_candidates()` silently skipped
  the genus and a real congener was never restored. **The response was to
  delete the caching entirely**, not to add a staleness check. The comment in
  `PtConceptionWorkflow_12S_single_site.R` says so explicitly: "removed rather
  than patched with a staleness check, so this step can never again silently
  serve stale reference data."
- **2026-09-14, nothing cached.** Because of that removal, every run now
  re-issues roughly 214 NCBI count queries plus a full sequence fetch before
  anything else happens. That is the redundant processing the user is worried
  about, and it is also what repeatedly exposes the run to transient NCBI
  failures. One such burst caused the incident above.

Neither failure was really about caching. **Both were about staleness
detection.** And the ecosystem already invented the right primitive in
September: `.cache_ok(path, inputs = ...)`, which rejects a cache whose
declared inputs are newer. It was never applied back to the reference fetch.
Deleting a cache because it lacked a staleness check, and then months later
building a staleness check and not reusing it, is exactly the tail-chasing
this review should end.

## Measured current state (2026-09-14)

| fact | value |
|---|---|
| packages with cache-taking functions | 7 of 9 |
| source files referencing `cache_dir` | 26 |
| package-level clear functions | 5, over 1 shared engine (`TaxaTools::report_and_clear_cache()`) |
| ecosystem-level clear or report | none |
| default cache location | `tools::R_user_dir("<pkg>", "cache")`, a hidden per-user directory |
| known size incidents | 23 GB, then 17 GB (38 GBIF zips at 17.0 GB against 52 MB for every other cache file combined) |

## The three questions, with a starting position

Answer these deliberately; do not assume the position below is right.

**1. Does the user keep control?** Only partly, today. `cache_dir` is a
parameter, so a caller CAN redirect it, but most functions default it to a
hidden user directory the analyst never chose and cannot see from the
project. So caching is ON by default without anyone asking for it, and its
artifacts live outside the project they belong to. Clearing requires knowing
which of five package-specific functions to call. The size incidents show the
hard-drive worry is not hypothetical.

**2. Internal or external decision?** Starting position: the *mechanism*
belongs inside the function, and the existing convention there is already
good (content-keyed per-file `.rds`, full key stored inside and verified on
read, so a key collision costs one recomputation and can never return another
taxon's answer). The *decision* should be external, driven by a
caller-supplied directory, with no caching when none is supplied. That is
roughly the current shape, but the `R_user_dir()` defaults undercut it.
Consider making `cache_dir = NULL` the default everywhere, so a workflow opts
in and the cache lands in the project beside the checkpoints it derives from.

**3. Should this be systematic?** Yes. Candidate scope:
   - One documented policy, applied across all 26 files.
   - `cache_dir = NULL` (off) as the uniform default; workflows opt in.
   - **Mandatory input declaration.** Any cache that derives from another
     artifact must name it, the way `.cache_ok(inputs = )` already does, so
     staleness is detected rather than designed around by deleting the cache.
   - One ecosystem-level `taxaid_cache_report()` / `taxaid_cache_clear()`
     over the existing shared engine, with per-package functions retained.
   - A size budget and reporting, given the two multi-GB incidents.
   - Re-examine the 2026-07-13 removal: with input-declared staleness, the
     reference fetch could be cached again safely, which would remove ~214
     redundant NCBI count queries per run and with them the exposure that
     caused the 2026-09-14 incident.

## Explicit non-goals

- Do not fold this into a bug fix.
- Do not change caching behaviour in any function without first deciding the
  policy above, in writing, with the user.

## Related

- `ecosystem_docs/fable_ecosystem_review_2026-09-13.md` Section O.
- `TaxaID/CLAUDE.md`, "A cache gate that tests only file.exists() silently
  serves stale results" under Known R Footguns.
- `PtConceptionWorkflow_12S_single_site.R`, the no-cache comment above the
  `fetch_ncbi_reference_sequences()` call.
