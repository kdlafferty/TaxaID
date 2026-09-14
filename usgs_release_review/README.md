# USGS WERC software-release review

The formal review of this repository ahead of its USGS software release, kept
here so the record and the reviewer's own corrected files stay together. This
folder is deliberately **outside every package** -- it documents the release,
it is not part of any package's source.

Previously called `misc review docs/`, which undersold it badly enough that it
sat untracked and unexplained for months. Renamed 2026-09-14.

## Contents

| file | what it is |
|---|---|
| `WERCReview.docx` | the reviewer's comments |
| `WERC_Software_Checklist.pdf` | the WERC release checklist (moved out of `inst/`) |
| `USGS_Software_Releases_guidance.pdf` | USGS release guidance (moved out of `inst/`) |
| `reviewer_supplied_README.md` | the README the reviewer rewrote and supplied |
| `reviewer_supplied_code.json` | the `code.json` the reviewer supplied, on the USGS template |

The two supplied files are the reviewer's versions, kept as provenance for
changes already made in the live repository. They are **not** the live files:
the live ones are `README.md` and `code.json` at the repository root, and both
have moved on since (the live README, for example, corrects theta from
"species occurrence probability" to "expected species composition -- each
taxon's relative share of the detections", which the supplied copy predates).

## Status of the review's requests, checked 2026-09-14

| request | status |
|---|---|
| README title with a colon, not a dash | done |
| `code.json` on the USGS Software template, CC0 | done |
| Remove LICENSE and DISCLAIMER from each package folder | done, none remain |
| Remove the Disclaimer from each package README | done |
| `renv/` -- needed for publishing? | removed |
| `POLISHING_ROADMAP.md`, `TODO_PUBLICATION.md` | removed |
| `TaxaID_Git_Setup.md` | removed |
| `ecosystem_docs/INTRO.md` -- outdated, addresses only 4 packages | removed; the two surviving `inst/` copies were removed 2026-09-14 |
| `TaxaID_presentation.qmd` -- what is this? | untracked 2026-09-14; kept on disk, not shipped |
| "Any test files should be deleted for final publication" | **not done, deliberately** -- see below |
| `CLAUDE.md` placement; `inst/` -> `llm`? | open, not decided |
| Link `ECOSYSTEM_WORKFLOW.md` / `PACKAGE_SETUP.md` from the README | open, not decided |
| `DESCRIPTION.md` content folded into package READMEs | open, not decided |

### On deleting test files

Not done, and the recommendation is to push back rather than comply. The nine
packages carry roughly 8,000 tests; they are how several real defects were
caught during September 2026 alone, and a standard R package ships its
`tests/` directory. The request most likely meant scratch and development
scripts rather than the test suite, and that reading should be confirmed with
the reviewer before anything is deleted.

## Related, deliberately NOT moved here

- `inst/Code and Domain Review 2.Rmd` -- a *different* review (the per-package
  code and domain review by Micah Wright). It is cited by ten files, including
  each package's own `inst/*_review_response.md`, so it stays where those
  references point.
- Each package's `inst/*_review_response.md` -- responses to that code review,
  not to this release review. They stay with their packages.

No written response to *this* release review exists in the repository. If one
was drafted elsewhere, it belongs here.
