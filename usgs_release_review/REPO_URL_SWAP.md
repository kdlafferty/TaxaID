# Repository URL swap list

TaxaID is expected to be released through a USGS-operated GitHub
organization. Until that URL is issued, `https://github.com/kdlafferty/TaxaID`
stands in for it. This file lists every place the placeholder appears, so the
final URL can be substituted in one pass and the result verified rather than
hoped for.

Generated from the tree, not maintained by hand. Regenerate it if the counts
move.

## Swap these

22 files, 54 occurrences.

| File | Occurrences |
|---|---|
| `DESCRIPTION` | 2 |
| `README.md` | 4 |
| `TaxaAssign/DESCRIPTION` | 2 |
| `TaxaAssign/README.md` | 3 |
| `TaxaExpect/DESCRIPTION` | 2 |
| `TaxaExpect/README.md` | 3 |
| `TaxaFetch/DESCRIPTION` | 2 |
| `TaxaFetch/README.md` | 2 |
| `TaxaFlag/DESCRIPTION` | 2 |
| `TaxaFlag/README.md` | 3 |
| `TaxaHabitat/DESCRIPTION` | 2 |
| `TaxaHabitat/README.md` | 3 |
| `TaxaLikely/DESCRIPTION` | 2 |
| `TaxaLikely/README.md` | 4 |
| `TaxaMatch/DESCRIPTION` | 2 |
| `TaxaMatch/README.md` | 3 |
| `TaxaTools/DESCRIPTION` | 2 |
| `TaxaTools/README.md` | 3 |
| `TaxaWizard/DESCRIPTION` | 2 |
| `TaxaWizard/R/shiny.R` | 2 |
| `TaxaWizard/README.md` | 3 |
| `code.json` | 1 |

## Do not swap this

| File | Occurrences | Why |
|---|---|---|
| `usgs_release_review/reviewer_supplied_code.json` | 1 | The reviewer's own artifact. It records what they were supplied and must not be edited. |

## Two that matter more than the prose

- Each `DESCRIPTION`'s `URL` and `BugReports` fields. R tooling reads these.
- `code.json`. This is the USGS software-release metadata.

The maintainer's instruction is to leave the `DESCRIPTION` fields until USGS
issues the new URL, rather than guessing at it now.

## One that is easy to forget

`TaxaWizard/R/shiny.R` holds the URL inside the Shiny application TaxaWizard
*generates*. A stale URL there is written into every app a user creates, which
makes it the highest-consequence occurrence and the one least likely to be
noticed. It is code, not prose.

## Verifying the swap

After replacing the URL, this command must return only the reviewer's file and
this document:

```sh
grep -rl "github.com/kdlafferty/TaxaID" \
  --include='*.md' --include='*.json' --include=DESCRIPTION \
  --include='*.R' --include='*.Rmd' --include='*.yaml' --include='*.yml' . \
  | grep -v llm_prompts/
```

Anything else in that output is a place the swap missed. Note that
`llm_prompts/` is excluded because it is generated: the prompt pack contains
zero occurrences of the URL, and regenerating it cannot introduce any.
