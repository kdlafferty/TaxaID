# Repository URL swap

TaxaID moved from `https://github.com/kdlafferty/TaxaID` to the USGS-operated
GitHub organization, `https://github.com/DOI-USGS/TaxaID`. The swap was made
in one pass, on 2026-11-10, ahead of the repository transfer.

## What was swapped

Every occurrence of `kdlafferty/TaxaID` in 41 files, 91 lines:

- each package `DESCRIPTION`'s `URL` and `BugReports` fields, and the
  meta-package's `Remotes`, which R tooling reads;
- every `README.md`, `inst/CITATION` and `man/*-package.Rd`;
- `code.json`, which also gained `homepageURL` and `downloadURL`, and whose
  `disclaimerURL` now points at the repository's own `DISCLAIMER.md`, matching
  other DOI-USGS repositories;
- three lines of code: the repository link inside the Shiny application that
  `TaxaWizard/R/shiny.R` generates (written into every app a user creates),
  the `install_github()` line `TaxaWizard/R/setup.R` writes, and the
  informational `github_url` in `TaxaTools/inst/model_tiers.json`.

## Not swapped

| File | Why |
|---|---|
| `usgs_release_review/reviewer_supplied_code.json` | The reviewer's own artifact. It records what they were supplied and must not be edited. |
| `usgs_release_review/reviewer_supplied_README.md` | The same. |
| This file | It names the old URL to say what moved. |

## Verifying the swap

This command must return only the three files above:

```sh
git grep -l "kdlafferty/TaxaID"
```

`llm_prompts/` is generated; it is regenerated after the swap, so it carries
the new URL wherever a README's Quick Start does.
