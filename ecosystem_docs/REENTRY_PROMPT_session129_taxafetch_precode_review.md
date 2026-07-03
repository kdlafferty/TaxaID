# Re-entry Prompt — TaxaFetch Pre-Code-Review Cleanup (PRIORITY: upcoming code review)

**Status:** TaxaFetch is scheduled for code review soon. This is a dedicated,
prioritized prompt for getting it ready — pulled out of the general Session 129
reentry prompt (`REENTRY_PROMPT_session129_calibration_resolved.md`), where the stale
test files were only a secondary item. Follow the established pre-review checklist
(memory: `reference_pre_review_checklist`, built from TaxaTools/TaxaMatch's Session
122 cycle, **extended this session to a 9-pass version** after comparing against a
real WERC review prompt a human reviewer is using in parallel on TaxaMatch — two
passes were previously missing entirely: documentation completeness, and vulnerability/
algorithm review). Passes below are ordered; do them in order.

**Top priority within this: Pass 1's stale test files — DONE.** `TaxaFetch/tests/testthat/
test-build_iucn_scheme.R`, `test-llm_api_utils.R`, and
`test-parse_hierarchical_habitat_response.R` tested functions that moved to
`TaxaHabitat`/`TaxaTools` in the Session 28 package split and no longer existed in
`TaxaFetch` at all. Confirmed via `grep` that none of these functions existed anywhere
in TaxaFetch's `R/` directory, and via `git log` that these test files predated all
tracked history. **Deleted this session.** Post-deletion, `devtools::test()`: 0
failures, 0 errors; `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Bonus finding while re-verifying:** a bare `testthat::test_dir("tests/testthat")` run
(not `devtools::test()`) initially showed a *4th* apparently-stale file,
`test-biotime_fetch.R` (`could not find function "read_biotime_study"`) — this looked
identical to the 3 genuinely-stale files above but was a false alarm: `read_biotime_
study()` is a real, correctly-exported function in `R/biotime_fetch.R`. Root cause: bare
`test_dir()` doesn't `load_all()`/attach the package first, so any test can spuriously
fail this way. This is almost certainly the explanation for the `check()`-vs-`test_dir()`
discrepancy flagged as unresolved in the general Session 129 reentry prompt — now
resolved and written into the checklist memory's Pass 6. **Takeaway for the rest of this
prep: always verify a suspected-stale test file's target function with `grep` (or
`devtools::load_all(); exists("fn_name")`) before deleting — a bare `test_dir()` failure
alone is not sufficient evidence.**

---

## Pass 1 — Debris cleanup

1. ~~Delete the 3 stale test files~~ — **done.**
2. Beyond those 3 files, a full debris sweep hasn't been done for TaxaFetch this
   session — check for: `dev/` scripts, a stale `README.Rmd` if `README.md` already
   exists and is current, leftover `.rds`/large data files at package root, old
   `inst/` scripts that are no longer maintained. Not yet checked.
3. Confirm `.Rbuildignore` covers all non-package files (`.lintr`, `CLAUDE.md`, `dev/`,
   `.Rhistory`, `.DS_Store`). Not yet checked.

## Pass 2 — Non-ASCII characters

Not yet run for TaxaFetch specifically this session (only the new
`get_gbif_occurrences.R` was checked directly, and it's clean — the package as a whole
has not been swept):
```r
grep -rn "[^\x00-\x7F]" R/
```
Common culprits: em-dashes (`—` → `--`), multiplication sign (`×` → `x`), approximately
(`≈` → `~=`), smart quotes.

## Pass 3 — Function and argument name review

Not yet done for TaxaFetch this session. One related finding worth folding in here:
this session found (and corrected in `TaxaFetch/CLAUDE.md`, but did NOT change in code,
since neither existing backend function was touched by design) that
`download_gbif_occurrences()`'s own documentation claimed it renames the SIMPLE_CSV
`issue` column to `issues` — it doesn't, confirmed directly against real cached data.
Worth a second look during this pass at whether other documented-vs-actual behavior
gaps exist in `R/download_gbif_occurrences.R` or `R/fetch_gbif_occurrences.R`, since one
was just found there by coincidence, not by a deliberate audit.

## Pass 4 — Documentation completeness (new pass, not yet run for TaxaFetch)

For every exported function (check `NAMESPACE`), confirm roxygen has: description,
every real argument documented in `@param` (and no stale `@param` for removed args),
`@return` describing the actual structure, and `@examples`. `get_gbif_occurrences()`
(this session's new function) already has full roxygen with a `\dontrun{}` example —
use it as the reference standard for this pass, not as something to re-check itself.
Prioritize `download_gbif_occurrences()` and `fetch_gbif_occurrences()` given Pass 3's
finding — if one had a wrong behavioral claim, worth checking the rest of their
roxygen carefully too, not just the one already-caught line.

## Pass 5 — lintr sweep

Not yet run for TaxaFetch. Check whether `.lintr` already exists in the package root;
create it if not (see the checklist memory for the standard config). Run
`lintr::lint_package()`, filter to `R/` issues, work through in priority order
(`object_usage_linter` → `object_length_linter` → `brace_linter` → `line_length_linter`
→ `commented_code_linter` → `spaces_inside_linter` → `trailing_blank_lines_linter` →
`return_linter`). Do not lint `inst/workflows/*.R` — those are working scripts, not
package source, and ALLCAPS constants / commented-out example lines there are
acceptable.

## Pass 6 — devtools::check() AND devtools::test() run separately — DONE, clean

Re-run after Pass 1's deletions: `devtools::test()` → 0 failures, 0 errors (2 expected
skips for live-API tests, 4 expected warnings from tests deliberately checking warning
messages). `devtools::check()` → 0 errors, 0 warnings, 0 notes.

The earlier `check()`-vs-`test_dir()` discrepancy is now root-caused, not just
worked around: bare `testthat::test_dir()` doesn't `load_all()`/attach the package
first, so it can spuriously report "function not found" for real, correctly-exported
functions (this nearly caused a 4th, incorrect deletion — see the top-of-file note).
`devtools::check()`'s bundled test run does the equivalent of `load_all()` first, which
is why its summary was trustworthy the whole time. Written into the checklist memory's
Pass 6 as the general rule: use `devtools::test()`, never bare `test_dir()`, when a
test-failure result needs to be trusted.

## Pass 7 — Vulnerability and algorithm/domain-correctness review (new pass, not yet run for TaxaFetch)

Two distinct checks, neither done for TaxaFetch yet this session:

- **7a — Vulnerabilities**: run `/security-review` against TaxaFetch. This package
  makes real network calls (GBIF, DataONE, literature/PDF sources) and handles
  user-supplied paths/credentials (`GBIF_USER`/`GBIF_PWD`/`GBIF_EMAIL` from
  `~/.Renviron`) — worth a real look, not assumed clean by default.
- **7b — Algorithms/scientific rigor**: a deliberate read-through of the GBIF fetch
  logic and predicate construction against what it's actually supposed to do (not a
  mechanical check) — `/code-review` (high or max effort) is a reasonable starting
  tool for this, but per the checklist memory's own note, actually running the
  package's real workflows against real data and checking the numbers make sense is
  the more valuable check and doesn't substitute well for a static tool alone.
  `get_gbif_occurrences()` was verified this way already (live-tested against real
  GBIF, validated against a real cached SIMPLE_CSV file) — the two older backend
  functions it wraps have not been freshly re-verified this session, only reused.

## Pass 8 — Update CLAUDE.md

Partially done — `TaxaFetch/CLAUDE.md` already has a Session 129 note for
`get_gbif_occurrences()` and the stale-test-file finding. Add a follow-up note once
Pass 1's deletion actually happens (don't leave the CLAUDE.md note saying "found, not
yet deleted" after it's been deleted), and note whatever Passes 4/5/7 turn up.

## Pass 9 — Commit

Standard commit message convention (see recent `git log` in this repo for examples):
```
TaxaFetch: remove stale test files from the Session 28 package split

test-build_iucn_scheme.R, test-llm_api_utils.R, and
test-parse_hierarchical_habitat_response.R test functions that moved to
TaxaHabitat/TaxaTools ~90 sessions ago and no longer exist in this package.
Confirmed via grep (functions absent from R/) and git log (predate all
tracked history). devtools::test(): <fill in final count> expectations,
0 failures, 0 errors.
```

---

## Process notes

- This is a deletion-heavy task (Pass 1) — confirm with the user before executing,
  even though the evidence here is about as unambiguous as it gets for stale test
  files (functions verifiably absent from the package, files verifiably predating all
  git history).
- Pass 6's `check()`-vs-`test_dir()` discrepancy is worth understanding properly during
  this pass, not just worked around — if it turns out `devtools::check()` genuinely
  doesn't surface testthat failures the way assumed, that's useful to know for every
  other package's pre-review pass too, not just TaxaFetch's.
- The user mentioned a human reviewer is running a per-file WERC-template review
  (via a separate DOI-provisioned Claude access) on TaxaMatch in parallel — worth
  asking whether they've since shared specific TaxaMatch findings that generalize to
  TaxaFetch (the two packages share some history, e.g. both went through the Session
  28 split), before assuming this checklist alone covers everything a human reviewer
  will find.
