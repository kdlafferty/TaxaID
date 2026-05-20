# Package Setup Guide — taxa_id Ecosystem

This document records the steps used to create each package in the `taxa_id` ecosystem.
Follow these steps when creating a new package or when onboarding a collaborator.

---

## Prerequisites

Install the required development packages if not already present:

```r
install.packages(c("usethis", "devtools", "roxygen2", "testthat", "cli"))
```

Confirm git is installed by typing this in the RStudio Terminal:

```bash
git --version
```

If git is not installed, download it from https://git-scm.com

---

## One-Time Git Configuration

This only needs to be done once per machine. In the RStudio Terminal:

```bash
git config --global --replace-all user.name "Your Name"
git config --global --replace-all user.email "your.email@domain.com"
```

Verify the config looks clean (should show exactly one name and one email):

```bash
git config --global --list
```

If you see malformed entries (lines without a section header like `[user]`), 
open and manually edit the config file:

```bash
open ~/.gitconfig
```

The file should look exactly like this and nothing else:

```
[user]
        name = Your Name
        email = your.email@domain.com
```

---

## Creating a New Package

Run these steps in order. Do them one package at a time — RStudio will 
restart and switch projects partway through.

### Step 1 — Create the package scaffold

Run in the R console. Replace the path with the correct package name:

```r
usethis::create_package("~/My Drive/Rscripts/projects/PackageName")#TaxaAssign, TaxaTools, TaxaExpect, TaxaMatch
```

This creates the folder, populates the package skeleton (DESCRIPTION, NAMESPACE, R/),
and opens the new package as an RStudio Project automatically.

### Step 2 — Initialize git

```r
usethis::use_git()
```

When prompted:
- **"Is it ok to commit them?"** → Yes
- **"A restart of RStudio is required. Restart now?"** → Yes

RStudio will restart and reopen the project. The Git pane will now be visible 
in the top-right panel.

### Step 3 — Create the dev folder

```r
dir.create("dev")
usethis::use_build_ignore("dev")
```

This creates the dev folder and tells R to ignore it when building the package.

### Step 4 — Set up testing infrastructure

```r
usethis::use_testthat()
```

This creates the `tests/testthat/` folder structure.

### Step 5 — Set up roxygen2 documentation

```r
usethis::use_roxygen_md()
```

This configures the package to use roxygen2 with markdown support in documentation.

### Step 6 — Add a README

```r
usethis::use_readme_rmd()
```

### Step 7 — Add a NEWS file for tracking changes

```r
usethis::use_news_md()
```

### Step 8 — Commit the scaffold

In the RStudio Git pane (top-right panel):
1. Check the box next to all files to stage them
2. Click **Commit**
3. Type a commit message: `Initial package scaffold`
4. Click **Commit**

### Step 9 — Copy in blueprint and intro files

Copy the relevant files from `ecosystem_docs/` into the package root:
- `BLUEPRINT_taxa_[name].md` → rename to `BLUEPRINT.md` in the package root
- `INTRO.md` → copy as-is into the package root

### Step 10 — Add core dependencies

Add packages this package will depend on. Run one line per dependency:

```r
usethis::use_package("dplyr")
usethis::use_package("tidyr")
usethis::use_package("cli")
usethis::use_package("TaxaTools")   # for TaxaMatch, TaxaExpect, TaxaAssign
```

For suggested (optional) dependencies:
```r
usethis::use_package("taxa_match", type = "Suggests")
usethis::use_package("taxa_expect", type = "Suggests")
```

### Step 11 — Final commit

Commit all the changes from steps 3 through 10:
- Stage all files in the Git pane
- Commit message: `Package infrastructure complete`

---

## Packages Created and Their Paths

| Package | Local Path | Date Created | Notes |
|---------|-----------|--------------|-------|
| `TaxaTools` | `~/My Drive/Rscripts/projects/TaxaID//TaxaTools/` | 2026-02-18 |Draft functions exist, not yet migrated |
| `TaxaMatch` | `~/My Drive/Rscripts/projects/TaxaID/TaxaMatch/` | 2026-02-18 | Draft functions exist, not yet migrated |
| `TaxaExpect` | `~/My Drive/Rscripts/projects/TaxaID/TaxaExpect/` | 2026-02-18 | Draft functions exist, not yet migrated |
| `TaxaAssign` | `~/My Drive/Rscripts/projects/TaxaID/TaxaAssign/` | 2026-02-18 | Draft functions exist, not yet migrated |

---

## Daily Development Workflow

These four commands will become muscle memory. Run them in the console 
from inside the relevant package project:

```r
devtools::load_all()    # reload package after editing any function
devtools::test()        # run all tests
devtools::document()    # rebuild roxygen documentation
devtools::check()       # full CRAN compliance check — run before major commits
```

---

## Committing Changes (the git habit)

**Always commit before starting a session that will modify code.**
That commit is your rollback point.

In the RStudio Git pane:
1. Stage files by checking boxes
2. Click Commit
3. Write a short descriptive message (e.g., `Add build_priors() function`)
4. Click Commit

To roll back to a previous commit if something goes wrong, use the 
RStudio Git History view or the Terminal:

```bash
git log --oneline          # see recent commits and their IDs
git checkout [commit-id]   # temporarily go back to that state
```
## Tracking Changes (UPDATING THE BLUEPRINT)
the blueprint is a list of working functions and AI will use it as 
a reference.  You need to update this in R manually (Open in Text Edit).
AI can indicate what to change if asked. Or, use 
ls(getNamespace("TaxaTools")) to make a list of functions loaded into the package
then compare that with the BLUEPRINT, and update as needed.

## Working with AI Projects
1. Open the relevant AI project
2. If there have been changes to the BLUEPRINT, DESCRIPTION or INFO, upload the new versions. This is the context for the chat.
2. Start a new chat — AI reads the previously uploaded files automatically
3. AI produces code in the chat
4. You copy-paste that code into RStudio
5. You save the file in RStudio
6. You run devtools::load_all() to test it
7. When happy, you commit via the Git pane
8. If the BLUEPRINT changed, you update it on your computer,
   then re-upload to the AI project
---

## Notes and Troubleshooting

**If the Git pane doesn't appear:** Close and reopen the project via 
File → Recent Projects. If still missing, run `usethis::use_git()` again.
