# Re-entry Prompt — TaxaFetch Pre-Code-Review Cleanup (PRIORITY: upcoming code review)

**Status:** TaxaFetch is scheduled for code review soon. This is a dedicated,
prioritized prompt for getting it ready — pulled out of the general Session 129
reentry prompt (`REENTRY_PROMPT_session129_calibration_resolved.md`), where the stale
test files were only a secondary item. Follow the established pre-review checklist
(same one used for TaxaTools + TaxaMatch's Session 122 review cycle), applied to
TaxaFetch specifically. Passes are ordered; do them in order.

**Top priority within this: Pass 1's stale test files.** Confirmed this session, not
yet deleted (deletion needs your go-ahead, not done silently): `TaxaFetch/tests/testthat/
test-build_iucn_scheme.R`, `test-llm_api_utils.R`, and
`test-parse_hierarchical_habitat_response.R` all test functions that moved to
`TaxaHabitat`/`TaxaTools` in the Session 28 package split and no longer exist in
`TaxaFetch` at all (`build_iucn_scheme()` → `TaxaHabitat`; `call_gemini_api()`/
`call_openai_api()`/`call_anthropic_api()` → `TaxaTools`; `parse_hierarchical_habitat_
response()` → `TaxaHabitat`). Confirmed via `grep` that none of these functions exist
anywhere in TaxaFetch's `R/` directory, and via `git log` that these test files predate
all tracked history — this is not a recent regression, it is leftover debris from a
~90-session-old package split that was never cleaned up. **A reviewer running
`devtools::test()` on TaxaFetch today will see 2 failures and 67 errors** unless this is
fixed first. Excluding these 3 files, the real suite is clean: 396 expectations, 0
failures, 0 errors.

---

## Pass 1 — Debris cleanup

1. **Delete the 3 stale test files above** (once you've confirmed — this is a
   deletion, so per this project's own standing rule it needs your explicit go-ahead,
   not something to do silently even though the evidence is about as clear as it gets).
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

## Pass 4 — lintr sweep

Not yet run for TaxaFetch. Check whether `.lintr` already exists in the package root;
create it if not (see the checklist reference for the standard config). Run
`lintr::lint_package()`, filter to `R/` issues, work through in priority order
(`object_usage_linter` → `object_length_linter` → `brace_linter` → `line_length_linter`
→ `commented_code_linter` → `spaces_inside_linter` → `trailing_blank_lines_linter` →
`return_linter`). Do not lint `inst/workflows/*.R` — those are working scripts, not
package source, and ALLCAPS constants / commented-out example lines there are
acceptable.

## Pass 5 — devtools::check()

Already run this session — **but the result needs re-verification after Pass 1's
deletions**, because of a discrepancy worth flagging precisely: `devtools::check()`'s
summary object reported 0 errors/0 warnings/0 notes for TaxaFetch even while
`testthat::test_dir()` independently showed 2 failed files (67 errors). Most likely
`check()`'s bundled test run and the summary parsing used this session didn't surface
testthat failures as check()-level errors the way expected — this was not chased down
to a definitive explanation. **Do not trust a bare `check()` summary alone for this
package until Pass 1 is done and `test_dir()` is re-run directly to confirm 0/0/0.**

## Pass 6 — Update CLAUDE.md

Partially done — `TaxaFetch/CLAUDE.md` already has a Session 129 note for
`get_gbif_occurrences()` and the stale-test-file finding. Add a follow-up note once
Pass 1's deletion actually happens (don't leave the CLAUDE.md note saying "found, not
yet deleted" after it's been deleted).

## Pass 7 — Commit

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
- Pass 5's `check()`-vs-`test_dir()` discrepancy is worth understanding properly during
  this pass, not just worked around — if it turns out `devtools::check()` genuinely
  doesn't surface testthat failures the way assumed, that's useful to know for every
  other package's pre-review pass too, not just TaxaFetch's.
