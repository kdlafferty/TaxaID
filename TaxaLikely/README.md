---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaLikely

Most taxonomic assignments rely on match scores (often percent
similarity). Users sometimes confuse a similarity score with the
probability that a match is correct, but a 99% similarity between an
observation and a reference is not the same as a 99% chance that the
observation is that species -- several species may be 99% similar.
To link scores to probabilities, match scores must first be converted
to likelihoods. TaxaLikely does this by fitting statistical models
that compare within-species scores to between-species scores in a
reference library. This process can also flag mislabeled references
(e.g., a sequence that matches other species better than its own).
Removing such errors improves assignment accuracy. TaxaLikely also
models the expected score profile of species absent from the reference
library, reducing false positives caused by missing references. By
replacing arbitrary score thresholds with continuous likelihoods,
TaxaLikely avoids both overconfident assignments and unnecessary loss
of taxonomic resolution. Calibrated likelihoods can then be multiplied
by priors (see TaxaExpect) to generate Bayesian posterior probabilities
for each hypothesized assignment. Part of the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem.

## Overview

TaxaLikely trains a hierarchical model on reference-vs-reference match
scores (DNA percent identity, image similarity, acoustic scores) and
applies it to convert per-observation scores into likelihoods. Supports
three hypothesis types:

-   **H1 (Known species)** -- target taxon is in the reference database
-   **H2 (Unreferenced species)** -- a congener absent from the
    reference
-   **H3 (Unreferenced genus)** -- a taxon from a different genus
    entirely

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaLikely")

# Bioconductor dependency for reference matrix building
BiocManager::install("DECIPHER")
```

## Quick Start

``` r
library(TaxaLikely)

# 1. Fetch reference sequences from NCBI
reference_df <- fetch_reference_sequences(
  taxa = c("Fundulidae", "Gobiidae"),
  barcode_term = "12S",
  rank = "family"
)

# 2. Build pairwise distance matrix
ref_matrix <- build_reference_matrix(reference_df)

# 3. Flag mislabeled references
errors <- flag_reference_errors(ref_matrix)

# 4. Train the likelihood model
model <- train_likelihood_model(ref_matrix)

# 5. Apply model to match data (from TaxaMatch)
result <- evaluate_likelihoods(match_df, model)
likelihoods <- result$likelihoods
# Columns: observation_id, taxon_name, hypothesis_type,
#           likelihood_point_est, likelihood_mean, likelihood_sd
```

## Key Functions

**Reference acquisition:** - `fetch_reference_sequences()` -- download
from NCBI by taxon + barcode marker - `read_reference_fasta()` -- load
local FASTA + taxonomy table

**Model training:** - `build_reference_matrix()` -- pairwise distance
matrix via DECIPHER - `flag_reference_errors()` -- detect mislabeled
references - `train_likelihood_model()` -- fit hierarchical Bayesian
model

**Inference:** - `evaluate_likelihoods()` -- convert match scores to
likelihoods - `filter_top_hypotheses()` -- keep finest-rank candidates
per query

**Reference QC:** - `audit_barcode_coverage()` -- find unreferenced
species (no barcode sequence) - `audit_reference_coverage()` --
taxonomic completeness check - `apply_coverage_constraints()` --
suppress H2 for fully-sampled genera - `remove_flagged_references()` --
clean match data using error flags

**Diagnostics and reporting:** - `interpret_model()` -- summarize
trained model parameters - `report_likelihood()` -- generate report
section for `assemble_report()`

## Statistical Design

-   Scores are logit-transformed and modelled as bivariate normal
    (score + gap)
-   Empirical Bayes shrinkage toward global mean for species-specific
    parameters
-   H2/H3 distributions shifted by learned delta offsets from H1
-   Perfect-match anchoring prevents penalizing 100% matches
-   Monte Carlo sampling provides `likelihood_mean` and `likelihood_sd`

## Vignettes

-   [Score to Likelihood](vignettes/score-to-likelihood.Rmd) -- full
    workflow

## Part of TaxaID

TaxaLikely receives match data from TaxaMatch and produces calibrated
likelihoods for TaxaAssign (posterior computation).

**Ecosystem:** TaxaMatch -\> **TaxaLikely** -\> TaxaAssign

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   TaxaTools (foundation package, installed first)
-   DECIPHER and Biostrings (Bioconductor; required for
    `build_reference_matrix()` only)
-   rentrez and xml2 (for NCBI reference fetching and coverage auditing)

All dependencies are declared in the DESCRIPTION file and installed
automatically.

## U.S. Geological Survey Disclaimer

This software is preliminary or provisional and is subject to revision.
It is being provided to meet the need for timely best science. The
software has not received final approval by the U.S. Geological Survey
(USGS). No warranty, expressed or implied, is made by the USGS or the
U.S. Government as to the functionality of the software and related
material nor shall the fact of release constitute any such warranty. The
software is provided on the condition that neither the USGS nor the U.S.
Government shall be held liable for any damages resulting from the
authorized or unauthorized use of the software.

*Non-endorsement of commercial products and services*: Any use of trade,
firm, or product names is for descriptive purposes only and does not
imply endorsement by the U.S. Government.
