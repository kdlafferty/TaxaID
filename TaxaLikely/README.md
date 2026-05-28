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

## Loading Pre-built Reference Databases

TaxaLikely supports several common reference database formats directly.

### CRABS (recommended for eDNA barcode databases)

[CRABS](https://github.com/gjeunen/reference_database_creator) (Creating
Reference databases for Amplicon-Based Sequencing) is a widely-used eDNA
reference database builder. Its internal format is a headerless
tab-delimited file with 11 fixed columns (accession through sequence).
Load it with:

``` r
ref <- read_crabs_output(
  file        = "mifish_12S_crabs.tsv",
  rank_system = c("family", "genus", "species"),  # or NULL to auto-detect
  max_n_bases = 250,      # optional: drop unusually long sequences
  dereplicate = TRUE      # optional: collapse identical seqs within species
)
```

**CRABS + TaxaLikely are complementary.** CRABS excels at bulk retrieval,
length filtering, primer trimming, and exact-sequence dereplication at
database-build time. TaxaLikely catches what CRABS cannot: mislabeled
sequences where the species annotation is wrong but the sequence itself is
valid. These produce within-species distances that look like between-species
distances and inflate false-positive rates. Always follow `read_crabs_output()`
with `flag_reference_errors()` on the alignment matrix to catch these:

``` r
ref_matrix <- build_sequence_matrix(ref)
errors     <- flag_reference_errors(ref_matrix)
clean_mat  <- remove_flagged_references(ref_matrix, errors)
model      <- train_likelihood_model(clean_mat)
```

### FASTA + separate taxonomy table

`read_reference_fasta()` accepts a FASTA file and a separate taxonomy source.
Two input formats are supported:

**Data frame** (custom databases, CRUX, GenBank dumps):

``` r
tax <- data.frame(
  composite_id = c("ACC001", "ACC002"),
  family  = c("Fundulidae", "Atherinopsidae"),
  genus   = c("Fundulus", "Atherinops"),
  species = c("Fundulus parvipinnis", "Atherinops affinis")
)
ref <- read_reference_fasta("sequences.fasta", taxonomy = tax,
                             rank_system = c("family", "genus", "species"))
```

**Taxonomy TSV file** (QIIME2 / RESCRIPt / SILVA / MIDORI2): supply
`taxonomy_file` instead of `taxonomy`. Both prefix-style
(`k__Kingdom;p__Phylum;...`) and positional (`Kingdom;Phylum;...`) formats
are auto-detected. Header rows are skipped automatically.

``` r
# Works with QIIME2 taxonomy artifacts, RESCRIPt output, or MIDORI2 files
ref <- read_reference_fasta(
  "sequences.fasta",
  rank_system   = c("family", "genus", "species"),
  taxonomy_file = "taxonomy.tsv"
)
```

## Key Functions

**Reference acquisition:** - `read_crabs_output()` -- load a CRABS
internal-format database (taxonomy embedded; no separate file needed) -
`fetch_reference_sequences()` -- download
from NCBI by taxon + barcode marker - `read_reference_fasta()` -- load
local FASTA + data-frame taxonomy (or `taxonomy_file` TSV for
QIIME2/RESCRIPt/MIDORI2) - `fetch_reference_recordings()` -- fetch
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
species (no barcode sequence; eDNA/DNA only) - `audit_acoustic_coverage()` --
find plausible species absent from classifier's known list (acoustic/image) -
`audit_reference_coverage()` -- taxonomic completeness check -
`apply_coverage_constraints()` -- suppress H2 for fully-sampled genera -
`remove_flagged_references()` -- clean match data using error flags (DNA only;
see `@section Scope:` in docs for acoustic/image guidance)

**Coverage quality filtering:** - `calibrate_coverage_filter()` --
sweep a grid of coverage thresholds and return breadth vs H1/H2
discrimination metrics (including Youden's J) to identify the
Pareto-optimal threshold - `coverage_threshold()` -- quick quantile-based
shortcut: set the threshold so that a target fraction (default 95%) of
pairs are retained, with automatic snapping to the nearest grade boundary
for categorical (acoustic) coverage

**Diagnostics and reporting:** - `interpret_model()` -- summarize
trained model parameters - `report_likelihood()` -- generate report
section for `assemble_report()`

## When to use `flag_reference_errors()`

`flag_reference_errors()` detects mislabeled sequences in a DNA reference
matrix. The function's applicability depends on the data source:

| Reference source | Use `flag_reference_errors()`? | Notes |
|---|---|---|
| **NCBI nucleotide** (via `fetch_reference_sequences()`) | **Yes — recommended** | NCBI has well-known curation issues: automated submissions, misidentified vouchers, contamination. Use routinely. |
| **Curated libraries** (CRUX, custom expert-built FASTA) | **Optional** | Lower mislabeling rate than NCBI, but flagging is still worth running. If your library has a quality column, use that filter instead. |
| **Xeno-canto bird sounds** (acoustic) | **No** | Xeno-canto is expert-curated; species identity mislabeling is rare. The dominant noise source is recording conditions (distance, background), not wrong species. Use `quality = c("A", "B")` in `fetch_reference_recordings()` instead. Hard-case recordings flagged by the mislabel detector may be legitimate. |
| **Camera trap images** (Animl/SpeciesNet) | **TBD** | Applicability is unknown. Camera trap ground-truth labeling has different error modes (occlusion, motion blur, multiple animals). Guidance will be added once image reference training workflows mature. |

## Reference Coverage Quality Filtering

Match scores (`p_match`) measure how similar two sequences or audio clips
are, but they do not capture *how much* of each observation contributed to
that score.  A 99% DNA identity computed from a 50 bp fragment of a 600 bp
barcode is far less reliable than the same identity computed from a 580 bp
overlap — yet both produce the same score.  Similarly, a high BirdNET
confidence from a poor-quality recording (heavy rain, distant call) carries
less information than the same score from a quiet, close-range recording.

Both build functions now attach a `coverage` column to their output,
placing DNA and acoustic reference data on a common [0, 1] scale:

- **`build_sequence_matrix()`** computes *alignment coverage*: the
  number of positions where both sequences contribute a non-gap character,
  divided by the shorter unaligned sequence length.  Values near 1.0
  indicate nearly complete overlap; values near 0.0 indicate highly gappy
  or partial alignments.

- **`build_acoustic_reference()`** maps Xeno-canto quality grades to a
  numeric scale: A → 1.0, B → 0.8, C → 0.5, D → 0.3, E → 0.1.  Grade
  reflects expert assessment of signal clarity and background noise.

### Choosing a threshold: `calibrate_coverage_filter()`

`calibrate_coverage_filter()` sweeps a grid of thresholds and returns
a data frame of per-threshold metrics:

| Metric | Description |
|---|---|
| `breadth` | Fraction of unique queries (`id_x`) surviving the filter |
| `h1_retention` | Fraction of within-species (H1) pairs retained |
| `h2_retention` | Fraction of cross-species (H2/H3) pairs retained |
| `youden_j` | `h1_retention − h2_retention` — Youden's J; **maximised at the Pareto-optimal threshold** |
| `discrimination` | `h1_retention / h2_retention` — ratio form; useful for log-scale plots |
| `mean_h1_score` | Mean `p_match` of retained H1 pairs |

**Youden's J** (sensitivity + specificity − 1 in ROC terminology) is the
primary selection criterion.  It is bounded [−1, 1], equals 0 at the
no-filter baseline, treats H1 retention and H2/H3 exclusion symmetrically,
and has no divide-by-zero edge case.  The threshold that maximises J retains
the most within-species signal while removing the most cross-species noise.

The `discrimination` column (ratio form) conveys the same information on a
multiplicative scale and is useful when plotting on a log axis.

**Note for acoustic data:** Xeno-canto quality grade is a property of the
recording, not the detection pair.  Every pair produced from the same
recording — both H1 and H2/H3 — carries the identical `coverage` value.
Filtering therefore removes entire recordings, excluding H1 and H2/H3 pairs
in equal proportion.  For acoustic data, `youden_j` and `discrimination`
will be near-flat; use `breadth` and `mean_h1_score` as the primary guides.
The function detects categorical coverage and emits a message in this case.

``` r
ref_matrix <- build_sequence_matrix(reference_df)

cal <- calibrate_coverage_filter(ref_matrix)

# Pareto-optimal threshold: maximises Youden's J
best <- cal[which.max(cal$youden_j), ]
cat("Threshold:", best$threshold,
    "| J =", round(best$youden_j, 3),
    "| breadth =", round(best$breadth, 3), "\n")

# Visualise the trade-off
plot(cal$breadth, cal$youden_j, type = "b",
     xlab = "Breadth (fraction of queries retained)",
     ylab = "Youden's J",
     main = "Coverage filter calibration")
abline(v = best$breadth, lty = 2, col = "red")

# Apply before training
ref_filtered <- ref_matrix[ref_matrix$coverage >= best$threshold, ]
model <- train_likelihood_model(ref_filtered)
```

### Quick alternative: `coverage_threshold()`

`coverage_threshold()` selects the threshold that retains a target
fraction of pairs by quantile — no H1/H2 structure required:

``` r
# Retain the best 90% of pairs by alignment coverage (discard bottom 10%)
thresh       <- coverage_threshold(ref_matrix, keep_frac = 0.90)
ref_filtered <- ref_matrix[ref_matrix$coverage >= thresh, ]
model        <- train_likelihood_model(ref_filtered)

# Acoustic: snaps to nearest Xeno-canto quality grade boundary
thresh <- coverage_threshold(ref_acoustic, keep_frac = 0.80)
# Message: "Snapping threshold 0.72 -> 0.80 (retains 83.1% of pairs, requested 80.0%)"
```

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

Developed with [Claude Code](https://claude.ai/code) (Anthropic).
