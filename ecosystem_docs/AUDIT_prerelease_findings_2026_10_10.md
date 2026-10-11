# Pre-release audit, 2026-10-10 (read-only findings)

Run after `main` was made public at `068d6ff` and tagged `calintertidal-R1009f`.
Nothing here was fixed; each item says what it is and what decision it needs.
Items 4, 10 and 12 of the maintainer's screen list.

## 1. The public citation block points at a 404

Every README tells a reader to cite a U.S. Geological Survey software release at
a DOI that does not exist:

```
Lafferty, K.D., 2026, TaxaID: A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.
```

`https://doi.org/10.5066/xxxxxx` returns **404**, and `R CMD check --as-cran`
reports it by name under "Found the following (possibly) invalid URLs". It
appears in **14 files**: the root README (twice), all nine package READMEs,
`inst/README.md` (twice, one of them `10.5066/xxxx` with four x's), and
`usgs_release_review/reviewer_supplied_README.md` (twice).

A previous screen logged this as a tracked release step and judged the
placeholder "correct for now", on the reasoning that the USGS DOI is assigned at
release. Two things have changed since that judgement:

- The repository is now public, so the broken placeholder is visible rather than
  pending.
- The maintainer declined the USGS provisional citation for the R1009f deposit
  ("no. this is not USGS data"). That answer was about the *data*, so it does not
  settle the *software* framing -- but every README currently asserts
  "U.S. Geological Survey software release" with the USGS `10.5066` prefix.

**Decision needed:** is TaxaID a USGS software release (keep the framing, fill the
DOI at release) or not (change the framing in ten READMEs)? Either way the
placeholder is now publicly 404. A previously reported companion defect,
`https://claude.ai/code` tool-attribution links in the nine package READMEs, has
since been fixed -- 0 occurrences remain.

## 2. Files the packages ship that look like review scaffolding

These live in `inst/` and therefore install into every user's library.
Reference counts exclude the file itself, and they matter -- a naive sweep would
have broken a man page and a test.

| File | Ships in | Referenced by | Safe to stop shipping? |
|---|---|---|---|
| `extra_functions_review_inputs.R` | 7 packages | `CLAUDE.md`, a re-entry prompt | Yes -- dev docs only |
| `test_api_keys.R` | TaxaTools | nothing | Yes |
| `draft_text_workflow.R` | TaxaTools | nothing | Yes |
| `test_overwrite_cache_manual.R` | TaxaFetch | `CLAUDE.md` | Yes |
| `review_function_inputs.R` | TaxaLikely, TaxaFetch | 40 files **including `TaxaLikely/man/restore_suppressed_candidates.Rd`** | No -- a shipped man page points at it |
| `pdf_workflow_test_v4.R` | TaxaFetch | **`TaxaFetch/tests/testthat/test-stack_occurrences.R`** | No -- a test depends on it |
| `test_blast_remote.R` | TaxaMatch | `TaxaMatch/inst/workflows/blast_sequences_workflow.R` | No -- a shipped workflow invokes it |

**Also:** `TaxaLikely/inst/TaxaLIkely_workflow.R` is misspelled -- capital `I` in
`LIkely`, in the package named TaxaLikely, shipped and public. Nothing references
it, so renaming is free.

## 3. Dated history in roxygen

The rule is that user-facing documentation describes current behaviour. A scan of
roxygen, package READMEs, NEWS and vignettes across all nine packages found 38
candidate lines; most are ordinary English ("a previously drawn polygon", "no
longer eligible") or dates inside `@examples` data, which are fine.

The genuine cluster is **`TaxaAssign/R/update_prior_from_consensus.R`**, five
lines that narrate this project's development with dates:

- `:87` "(2026-10-06) ring and named-row priors rose up to ~14,000-fold"
- `:177` "Measured on CalIntertidal (2026-10-07): raising a ..."
- `:190` "on CalIntertidal (2026-10-07, after the two guards above)"
- `:245` "**Until 2026-10-07** a row with no occurrence record ... was"
- `:321` "rows are no longer raised"

Four are mechanical: drop the parenthetical date, keep the measurement. `:245` is
not -- "Until <date> X was Y" has to be restated as what the behaviour *is*, which
is a real edit. Two more marginal cases: `TaxaAssign/R/assign_taxa_llm.R:176`
("That ceiling is now 16000 ... no longer has to") and
`TaxaWizard/R/registry.R:34` ("Current schema (5): \value is no longer
truncated"), both of which describe current state by reference to a change.

Fixing any of these re-documents the package, which changes `.Rd`, which changes
the prompt pack -- so it needs a regeneration and a pack-guard run, not just an
edit.

## 4. Where package code actually lives (item 12)

The concern was "six copies never merged into main" and "sixteen copies some
script loads from directly". Measured, it is smaller and more specific:

- **Three working trees of one repository**, not independent copies: the shared
  checkout at `My Drive/Rscripts/projects/TaxaID` (branch
  `workflow-ptcon-multisite`, `75c7342`), plus the `main` and `cp-index-split`
  worktrees. `ref-support` and `cite-prov` were merged and removed today.
- **One sibling repository**, `My Drive/Rscripts/projects/TaxaID_dev`, holding
  `diagnostics/` and its own `ecosystem_docs/`. 46 of its 97 scripts load package
  code from a folder, which is legitimate for diagnostics.
- **Two stray alternate libraries** -- the real hazard, because they hold *old
  installed code* that a stray `.libPaths()` would pick up silently:
  `~/.R_libs_blast_session` (TaxaMatch, built 2026-09-27) and
  `~/.R_libs_counts_branch` (TaxaExpect and TaxaFetch, built 2026-09-28).
- **One deliberate code snapshot** under
  `CaliforniaIntertidal/reporting/out/R1009f/code_2026-10-10/`, which is good
  provenance practice, not debris.

**Production scripts are already compliant.** The `eDNA/` workflows load packages
with `library(<pkg>)`, and no production script pins `.libPaths()` at a
non-standard library -- the apparent hits are `libpath = .libPaths()` passed
correctly to `callr`, plus one deliberate exclusion filter in a diagnostic. 39 of
605 `eDNA/` files use `load_all()`, and they are probes and one-off tests rather
than the workflows.

The maintainer's rule is adopted: merged code is loaded from the installed
package, and a script needing an exact older version pins a recorded commit, not
a directory. One addition, learned the hard way today -- **an installed package
records no commit.** Reconstructing which commit nine installed packages came
from took deparse-level comparison against candidate trees, because `DESCRIPTION`
carries only a timestamp. So "use the installed package" has to be paired with
"record what you loaded", as `CaliforniaIntertidalWorkflow_multi_marker.R`
already does via its per-package namespace code digest. And a commit pin is only
as good as its reachability: the five `archive/*` tags exist on no remote, so a
pin to one of those is exactly as fragile as a folder.

## Deliberately not done

No file was deleted, renamed, re-documented or pushed. Items 1-3 are release-content
decisions, and item 2 shows that two of the seven candidates are load-bearing.
