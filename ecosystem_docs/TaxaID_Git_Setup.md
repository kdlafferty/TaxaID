# TaxaID Ecosystem — Git Repository Setup Guide

**Prepared for:** Christina Flora  
**Project owner:** Kevin Lafferty (klafferty@usgs.gov)  
**Date:** 2026-03-05

---

## What This Is

TaxaID is a suite of four R packages that together implement a Bayesian framework
for taxonomic identification. The packages are designed for scientists working with
eDNA sequences, camera trap images, and acoustic recordings who need a principled,
reproducible approach to assigning taxonomic labels to observations.

All four packages are developed by Kevin Lafferty, USGS Western Ecological Research Center,
Santa Barbara Field Station. The goal of this setup is to bring that folder under
Git version control as a **mono-repository** — one repository containing all four
packages. That repository needs to be accessible to several people. The repository administrator,
Any potential reviewers, Richard Erickson, Kevin Lafferty through USGS, and colleagues through 
UCSB that may be testing the code. 

---

## Repository Structure

Because of the need to share between UCSB and USGS colleagues, the suggested folder to place under Git control is outside of USGS at:

```
~/My Drive/Rscripts/projects/TaxaID/
```

Its current contents (which become the repo root):

```
TaxaID/                              ← Git repo root
├── ecosystem_docs/                  ← shared documentation
├── TaxaAssign/                      ← R package
├── TaxaExpect/                      ← R package (most active)
├── TaxaMatch/                       ← R package
└── TaxaTools/                       ← R package
```

Each package subdirectory is a standard R package with its own `DESCRIPTION`,
`NAMESPACE`, `R/`, and `tests/` folders, and its own RStudio `.Rproj` file.

---

## The Four Packages

### TaxaTools
| | |
|---|---|
| **Status** | In development |
| **Purpose** | Taxonomy helper functions shared across the ecosystem |
| **R imports** | `dplyr`, `httr`, `jsonlite`, `purrr`, `rlang`, `stats`, `stringr`, `tidyr` |
| **External APIs** | Global Names Verifier API — no key required |
| **Description** | Verifies and cleans scientific names against taxonomic backbones (GBIF, NCBI, WoRMS, ITIS, Catalogue of Life). Resolves synonyms, retrieves taxon ranks and classification hierarchies. Used by all other packages. |

### TaxaMatch
| | |
|---|---|
| **Status** | Planned |
| **Purpose** | Convert reference-match scores into statistical likelihoods |
| **R imports** | TBD |
| **External APIs** | None |
| **Description** | Takes a similarity score (e.g. % sequence match between a sample and a reference library) and converts it to a likelihood — the probability that the match label is correct at each taxonomic rank. Handles taxa absent from the reference database and can flag probable errors in the reference database itself. |

### TaxaExpect
| | |
|---|---|
| **Status** | In active development |
| **Purpose** | Generate prior species occurrence probabilities using GBIF data and species distribution models |
| **R imports** | `httr2`, `dplyr`, `tidyr`, `tibble`, `rlang`, `glmmTMB`, `stringr`, `sf`, `terra`, `marmap`, `rnaturalearth`, `rnaturalearthdata`, `rnaturalearthhires`, `leaflet`, `leaflet.extras`, `shiny`, `miniUI`, `stats`, `utils` |
| **R suggests** | `rstudioapi`, `rgbif`, `TaxaTools`, `beepr`, `testthat` |
| **External APIs** | GBIF occurrence API; Anthropic Claude API (optional, for LLM habitat assignment); NOAA GEBCO bathymetry (downloaded and cached on first use) |
| **⚠️ Special install note** | Requires `rnaturalearthhires` from the rOpenSci r-universe, not CRAN. The `DESCRIPTION` file already contains `Additional_repositories: https://ropensci.r-universe.dev` — this line must be preserved, and any CI runner must have this repository configured. |
| **Description** | Downloads and filters GBIF occurrence records, assigns habitat (IUCN classification scheme or a user-defined custom scheme), fits hierarchical Bayesian models (binomial GLMMs via glmmTMB), and generates theta priors (occupancy × detectability) for each species × habitat × grid cell combination. Includes interactive Shiny/Leaflet tools for spatial data review. The most complex package in the ecosystem. |

### TaxaAssign
| | |
|---|---|
| **Status** | Early development |
| **Purpose** | Compute Bayesian posterior taxon assignment probabilities |
| **R imports** | `cli`, `dplyr`, `magrittr`, `purrr`, `rlang` |
| **External APIs** | None |
| **Description** | Applies Bayes' theorem: posterior = likelihood × prior (normalised). Requires a likelihood object from TaxaMatch and a prior object from TaxaExpect — or any externally generated inputs that conform to the shared interface. Outputs ranked taxonomic assignments with uncertainty estimates across ranks (species, genus, family, etc.). |

---

## Pipeline Logic

The packages form a sequential pipeline, but each can also be used standalone:

```
Raw sample (sequence / image / recording)
        │
        ▼
  TaxaTools ──────────────── name verification and taxonomy
        │
        ├─────────────────────────────────────┐
        ▼                                     ▼
  TaxaMatch                             TaxaExpect
  P(sample | taxon)                     P(taxon at site)
  likelihood object                     prior object
        │                                     │
        └──────────────┬──────────────────────┘
                       ▼
                 TaxaAssign
                 P(taxon | sample, site)
                 posterior object
```

TaxaAssign accepts any conforming likelihood or prior object — inputs do not
have to come from TaxaMatch/TaxaExpect specifically.

---

## Environment Variables — Never Commit These

TaxaExpect optionally calls an API for LLM-based habitat assignment.
The API key is stored as a user environment variable, never in source code.

| Variable | Used by | How it is set |
|---|---|---|
| `XXLLM_API_KEY` | `TaxaExpect::prompt_anthropic_api()` | Added to `~/.Renviron` as `XXLLM_API_KEY=sk-ant-...` |

The `.gitignore` below excludes `.Renviron` automatically. Please confirm with
Kevin that no API keys or credentials exist anywhere else in the project folder
before the first commit.

---

## Recommended `.gitignore`

Create this file at the **repo root** (`TaxaID/.gitignore`) before the first commit.

```gitignore
# R development artifacts
.Rproj.user/
.Rhistory
.RData
.Ruserdata

# R package build outputs
*/src/*.o
*/src/*.so
*/src/*.dll
*/.Rcheck/

# Runtime cache files (TaxaExpect downloads these at runtime)
*.nc
*.tif
*.asc
gbif_cache/

# Sensitive — API keys and personal config
.Renviron
*.env

# macOS
.DS_Store

```

> **Note on `man/` and `NAMESPACE`:** These are auto-generated by
> `devtools::document()` but should be **tracked in Git** so collaborators
> get a working package without needing to regenerate documentation locally.
> The `.gitignore` above does not exclude them.

---

## Initial Setup Steps

### Step 1 — Confirm prerequisites

```bash
# Run in Terminal (macOS)
git --version          # should return a version number
git config --global user.name
git config --global user.email
```

If identity is not configured:
```bash
git config --global user.name "Kevin Lafferty"
git config --global user.email "klafferty@usgs.gov"
```

### Step 2 — Create the remote repository

On GitHub (or your chosen platform), create a new empty repository named `TaxaID`.
Do **not** initialise it with a README or `.gitignore` — the local folder already
has content.

### Step 3 — Initialise Git locally

```bash
cd "/Users/lafferty/My Drive/Rscripts/projects/TaxaID"
git init
git remote add origin <remote-url>     # paste the URL from GitHub
```

### Step 4 — Add `.gitignore`, then make the initial commit

Create `TaxaID/.gitignore` with the contents above, then:

```bash
git add .
git commit -m "Initial commit: TaxaID ecosystem mono-repo (four R packages)"
git push -u origin main
```

### Step 5 — Create a development branch

```bash
git checkout -b dev
git push -u origin dev
```

Day-to-day work happens on `dev`. The `main` branch is updated by merging from
`dev` at stable milestones. This gives Kevin a clean rollback point at all times.

---

## Daily Developer Workflow (for reference)

Kevin works from inside each individual package's RStudio project. The Git pane
in RStudio handles staging and committing. Typical session:

1. Open the relevant package project (e.g. `TaxaExpect/TaxaExpect.Rproj`)
2. Make a commit in the Git pane **before** starting a major edit — this is the rollback point
3. Edit code, then reload and test in the R console:
   ```r
   devtools::load_all()    # reload package after editing
   devtools::test()        # run all tests
   devtools::document()    # rebuild docs if roxygen comments changed
   devtools::check()       # full R CMD check before major commits
   ```
4. Stage and commit in the RStudio Git pane with a short message
5. Push to `origin/dev`

---

## Key Files to Know About

| File | Location | Purpose |
|---|---|---|
| `AI_CONTEXT.md` | repo root | Context file for AI coding assistant used in development — do not delete or move |
| `INTRO.md` | `ecosystem_docs/` | Plain-language ecosystem overview for new contributors |
| `PACKAGE_SETUP.md` | `ecosystem_docs/` | Step-by-step guide for creating a new package or onboarding a collaborator |
| `BLUEPRINT.md` | `TaxaExpect/` | Detailed function inventory and design notes for TaxaExpect |
| `DESCRIPTION` | each package root | R package metadata including all dependencies — one per package |
| `NAMESPACE` | each package root | Auto-generated export list — tracked in Git, regenerated by `devtools::document()` |

---

## Questions for the Administrator

| Decision | Options | Notes |
|---|---|---|
| **Hosting platform** | GitHub, GitLab, Bitbucket | GitHub is most common for R packages; `devtools::install_github()` works natively |
| **Visibility** | Public or private | USGS projects may have institutional requirements |
| **Branch protection on `main`** | Require PR review or not | Single developer currently — likely not needed yet |
| **CI/CD** | GitHub Actions or none | The standard `r-lib/actions` workflow runs `R CMD check` on push; worth adding once packages stabilise; any runner will need the rOpenSci r-universe configured for `rnaturalearthhires` |
