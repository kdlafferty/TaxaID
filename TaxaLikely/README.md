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
ref_matrix <- build_sequence_matrix(reference_df)

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
local FASTA + taxonomy table - `fetch_reference_recordings()` -- fetch
bird sound recordings from Xeno-canto API v3 for acoustic model
training; returns metadata table with `file_url` for audio download
(requires free API key from `xeno-canto.org/account`, stored as
`XC_API_KEY` in `~/.Renviron`)

**Model training:** - `build_sequence_matrix()` -- pairwise distance
matrix via DECIPHER (DNA sequences) - `build_acoustic_reference()` --
join BirdNET detections to Xeno-canto ground truth, label H1/H2/H3,
produce pair format for `train_likelihood_model()` (acoustic) -
`flag_reference_errors()` -- detect mislabeled references -
`train_likelihood_model()` -- fit hierarchical Bayesian model

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

TaxaLikely models the joint distribution of two features -- the
logit-transformed match score (absolute fit) and the gap to the best
alternative (relative uniqueness) -- as a bivariate normal for each
hypothesis type:

-   **Score + gap features:** Raw scores are logit-transformed to an
    unbounded domain; the gap is computed in logit space so that
    differences near 100% are amplified appropriately
-   **Bivariate normal likelihood:** The joint (score, gap) density
    captures interactions -- a small gap is more tolerable when the
    score is very high
-   **Empirical Bayes shrinkage:** Per-species parameters are shrunk
    toward the global mean (Efron and Morris 1973), with weight
    inversely proportional to sample size, preventing poorly sampled
    species from having unreliable estimates
-   **H2/H3 offset distributions:** Unreferenced species and genus
    hypotheses use the H1 distribution shifted left by learned delta
    offsets, estimated from cross-species match scores in training
    data
-   **Perfect-match anchoring:** Synthetic 100% match pseudo-data
    prevent the "perfection penalty" where the Gaussian density peaks
    below 100%
-   **Monte Carlo uncertainty:** Score perturbation across simulations
    yields `likelihood_mean` and `likelihood_sd`, measuring sensitivity
    to measurement noise

For a detailed treatment of the statistical framework, feature
engineering, hypothesis definitions, parameter estimation, and
reference quality control, see
[`inst/TaxaLikely_supplemental_methods.md`](inst/TaxaLikely_supplemental_methods.md).

## Acoustic Workflow

For bird acoustic data, TaxaLikely integrates with BirdNET-Analyzer
via `TaxaMatch::read_birdnet_output()`. The reference training workflow
uses Xeno-canto recordings as ground-truth labels:

``` r
library(TaxaLikely)
library(TaxaMatch)

# 1. Fetch reference recordings from Xeno-canto (requires XC_API_KEY)
recs <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia"),
  quality         = c("A", "B"),
  max_per_species = 30L,
  download        = TRUE,
  download_dir    = "reference_audio/"
)

# 2. Run BirdNET-Analyzer on reference_audio/ (Python, outside R):
#    pip3 install birdnetlib
#    See TaxaMatch README for the analysis script.

# 3. Read BirdNET detections
birdnet_df <- read_birdnet_output("birdnet_results/", min_confidence = 0.1)

# 4. Join back to Xeno-canto ground truth via source_file → local_path
#    to label H1 (BirdNET detected correct species), H2 (wrong species,
#    same genus), H3 (wrong genus), then train the likelihood model:
# train_likelihood_model(labeled_df, rank_system = c("genus", "species"))
```

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
    `build_sequence_matrix()` only)
-   rentrez and xml2 (for NCBI reference fetching and coverage auditing)
-   httr2 (for `fetch_reference_recordings()`; Xeno-canto API v3)
-   Xeno-canto API key for `fetch_reference_recordings()` (free
    registration at `xeno-canto.org/account`; set `XC_API_KEY` in
    `~/.Renviron`)

All dependencies are declared in the DESCRIPTION file and installed
automatically.
