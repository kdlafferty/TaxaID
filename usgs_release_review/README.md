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
packages carry roughly 12,700 tests; they are how several real defects were
caught during September 2026 alone, and a standard R package ships its
`tests/` directory. The request most likely meant scratch and development
scripts rather than the test suite, and that reading should be confirmed with
the reviewer before anything is deleted.

## Notes for the technical reviewer: security posture

Checked against the WERC criteria on 2026-10-18, at `06d3ef3b`. Nothing here needs
a fix; it is written down so the review does not have to rediscover it.

**Where API keys come from, and where they go.** Keys are read only through
`Sys.getenv()` -- twelve call sites across seven variables
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `AZURE_OPENAI_API_KEY`,
`XAI_API_KEY`, `OPENALEX_API_KEY`, `XC_API_KEY`). No key material is committed:
every key-shaped string in the repository is either a documentation placeholder
(`sk-ant-your-key-here`, `AIza...`) or the string `"fake-key"` in a test. No code
path prints, logs, messages or writes a key.

**The one case that looks alarming and is already handled.** The Gemini request
sends its key as a URL query parameter rather than a header
(`TaxaTools/R/call_api.R`, `req_url_query(key = api_key)`). That is Google's
Generative Language API scheme, not a design choice. It means a connection error
raised by curl or httr2 can echo the full request URL -- including the key -- into
its condition message. The code strips it before that message is ever surfaced:

```r
# TaxaTools/R/call_api.R, in the req_perform() error handler
msg <- conditionMessage(e)
if (nzchar(api_key)) {
  msg <- gsub(api_key, "***REDACTED***", msg, fixed = TRUE)
}
```

All other providers pass the key in a header (`x-api-key`, `Authorization: Bearer`,
`api-key`). Every `stop()`, `message()` and `warning()` site in `call_api.R` was
checked: none includes the request URL, endpoint or request object.

**Outbound requests.** Three request builders (Anthropic, Gemini, OpenAI-compatible).
The optional `temperature` argument is validated -- rejected unless it is a single
finite non-negative number -- and is included in the request body only when it is not
`NULL`, so the default sends no temperature field at all. Note that some models reject
the parameter outright (HTTP 400, "temperature is deprecated for this model"), which
`call_api()` surfaces as the provider's own message.

**No dynamic code execution.** The 1.0 cycle added no `system()`, `system2()`,
`eval()`, `eval.parent()` or `parse(text = )` call, and no new deserialization of
external data (`readRDS`, `unserialize`, `load`).

**File writes.** Every cache is opt-in through a caller-supplied `cache_dir`, except
TaxaWizard's workflow registry and TaxaTools' model registry, both of which use a
fixed path documented in the root README's caching table. Cache filenames are built
from numeric hashes (`%010.0f-%010.0f-%06d`), so a taxon name cannot influence a path.

**Dependencies and licences.** No package's `DESCRIPTION` gained an `Imports`,
`Depends` or `Suggests` entry during the 1.0 cycle, so there is no new third-party
surface to assess. All nine packages are `License: CC0`, matching `code.json`'s
`CC0-1.0`. The USGS provisional disclaimer is present in the root README, and
`code.json` carries `status: Preliminary`.

## `WERC_README_template.md`

The WERC-supplied README template, moved here from the repository root's
`inst/` on the maintainer's instruction. It is a **blank template**, not a
description of this software: its title line reads `ADD SOFTWARE TITLE
(TEMPLATE)`, it carries a placeholder DOI twice, and its two image paths
(`media/usgs_green.png`, `media/orcid.gif`) resolve to nothing in this
repository and did so before the move.

It was shipping inside the `TaxaID` meta-package, so a reviewer opening the
package's own `inst/README.md` was told the software had no title. Moved
rather than deleted because it is the template the release is written
against, and left byte-for-byte unedited because it is a supplied artifact --
the same treatment as `reviewer_supplied_README.md`. The repository's real
front page is the root `README.md`, which is unaffected.

## Related, deliberately NOT moved here

- `inst/Code and Domain Review 2.Rmd` -- a *different* review (the per-package
  code and domain review by Micah Wright). It is cited by ten files, including
  each package's own `inst/*_review_response.md`, so it stays where those
  references point.
- Each package's `inst/*_review_response.md` -- responses to that code review,
  not to this release review. They stay with their packages.

The written response to this release review is `RESPONSE_to_release_review.md`
in this folder.
