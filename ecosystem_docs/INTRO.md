# TaxaID Ecosystem — Shared Introduction

## Purpose
The `TaxaID` ecosystem is a suite of four R packages that together implement a Bayesian 
framework for taxonomic identification and assignment. The ecosystem is designed for 
scientists who work with biodiversity data — including eDNA sequences, camera trap images, 
and acoustic recordings — and need a principled, reproducible approach to assigning 
taxonomic labels to observations while quantifying uncertainty.

The ecosystem is intended to be accessible to users who are not statisticians or 
programmers. Functions produce informative error messages, include input validation, 
and are documented with plain-language examples.

## The Four Packages

| Package | Role | Standalone Use |
|---------|------|----------------|
| `TaxaTools` | Shared taxonomy helper functions used by all other packages | Yes |
| `TaxaMatch` | Generates likelihood objects from reference database matching | Yes — reference database coverage and error checking |
| `TaxaExpect` | Generates prior objects via GBIF-based niche modeling | Yes — species distribution modeling and mapping |
| `TaxaAssign` | Combines likelihood and prior objects to compute Bayesian posteriors | Requires likelihood and prior inputs |

## Package Dependencies
```
TaxaTools
    ↑         ↑
TaxaMatch  TaxaExpect
    ↑         ↑
    TaxaAssign
```
`TaxaAssign` accepts inputs from `TaxaMatch` and `TaxaExpect` but is designed 
to accept any conforming likelihood or prior object, allowing users to supply 
inputs generated outside the ecosystem.

## Shared Conventions (apply to all packages)
- All functions use `package::function()` namespacing throughout
- All exported functions documented with `roxygen2` including `@examples`
- All exported functions validate inputs and return informative errors via `cli`
- Standard return object: tibble
- Naming convention: `verb_noun()` (e.g., `build_priors()`, `match_sequences()`)
- Renaming log maintained in each function file header when functions are renamed
- Tidyverse as default dependency; base R second; new dependencies flagged explicitly
- No hard coded inputs — all parameters exposed with sensible defaults
- No god functions — single responsibility per function (~30 lines guideline)
- Large input files assumed — performance-sensitive operations use `data.table` internally
- Progress reporting standardized across all heavy-lifting functions
- Liberal commenting explaining *why*, not just *what*

## Interface Contract
⚠️ PLACEHOLDER — to be defined via draft code session before development begins.
The likelihood object, prior object, and posterior object share a common column 
structure that ensures interoperability across packages. See individual package 
blueprints for package-specific details. The canonical column definitions will 
be recorded here once established.

**Likelihood object columns:** TBD  
**Prior object columns:** TBD  
**Posterior object columns:** TBD  
**Required vs optional fields:** TBD  

## Meta-package
`TaxaID` is the meta-package that loads all four component packages with a single 
`library(TaxaID)` call. It contains no functions of its own.
