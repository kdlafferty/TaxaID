---
editor_options:
  markdown:
    wrap: 72
---

# TaxaFlag

Post-assignment quality flagging for the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem. Identifies
anomalous detections in taxonomic assignment results using data-driven
and expert-review approaches.

Taxonomic assignment matches observations to identifications, but
samples often contain artifacts. TaxaFlag provides three independent
post-hoc checks:

-   **Contamination screening** compares taxon read counts against
    control samples (lab blanks, field blanks, positive controls). For
    example, in metabarcoding, human and food-related sequences
    commonly appear in blanks, and their relative frequency in controls
    can justify removal.
-   **Handler artifact detection** flags observations that fall within
    a time buffer around camera setup and retrieval, when human
    activity is expected.
-   **LLM expert review** uses a language model to assess whether each
    assignment is plausible given the habitat and geographic location,
    flagging unusual detections for closer inspection.

## Flagging Methods

| Method | Function | Data needed |
|------------------------|------------------------|------------------------|
| **Contamination** | `flag_contaminant()` | Read counts + control samples |
| **Handler artifacts** | `flag_handler()` | Timestamps + setup/retrieval times |
| **Expert review** | `review_assignments()` | Assignments + LLM API key |

Each method is independent -- use one, two, or all three depending on
your data type and available metadata. Flags are additive columns, not
filters. Together, these checks target false positives that survive
upstream statistical assignment: contamination, handler artifacts,
allochthonous transport (e.g., eDNA carried by currents from outside
the sampling area), and other ecologically implausible detections.

## Methods

### Contamination Scoring

`flag_contaminant()` compares the relative abundance of each taxon in
field samples versus control samples. Within each sample, read counts
are first converted to proportions (reads for taxon / total reads),
normalizing for sequencing depth. Proportions are then averaged across
field and control replicates, and a score is computed:

    score = mean_prop_field / (mean_prop_field + mean_prop_control)

Scores range from 0 (taxon found only in controls) to 1 (taxon found
only in field samples). Taxa absent from controls receive a score of
1.0; taxa absent from field samples receive 0.0. Default thresholds
classify scores as `"high"` risk (score ≤ 0.5, probable contaminant),
`"moderate"` risk (0.5 < score ≤ 0.9, ambiguous), or `"low"` risk
(score > 0.9, likely genuine detection). For positive controls, the
interpretation inverts: taxa from positive controls appearing in field
samples indicate cross-contamination.

### Handler Artifact Detection

`flag_handler()` identifies observations that fall within a time buffer
of camera setup or retrieval, when human activity is expected. For each
group (e.g., camera station), the function identifies the earliest and
latest timestamps as the sampling-period edges. Each observation
receives a linear score based on its proximity to the nearest edge:

    handler_score = minutes_to_nearest_edge / interval_minutes

clamped to [0, 1]. The default interval is 30 minutes. Observations
outside the interval score 1.0 (valid); those at the exact edge score
0.0 (probable artifact). When `handler_taxa` is specified (e.g.,
"Homo sapiens"), only those taxa are scored for temporal proximity --
other species detected near edges are assumed legitimate.

### LLM Expert Review

`review_assignments()` submits each unique taxon (in batches of 15) to
an LLM for structured assessment across eight dimensions: habitat fit,
geographic plausibility, taxonomic scope, contamination risk, plausible
alternatives, finer-rank hypotheses, confidence, and a free-text
comment. Plausibility columns use a consistent vocabulary:
`"likely"` / `"possible"` / `"unlikely"` (higher = more plausible
genuine detection). Contamination risk uses `"low"` / `"moderate"` /
`"high"` (higher = more contamination risk). The function includes
truncation recovery: if an LLM response is cut off mid-JSON, it walks
backward to find the last complete object and parses what is available.
Taxa omitted by the LLM are filled with NA. Supports eDNA, acoustic,
and image data via the `data_type` param. This review is intended as a
structured second opinion, not an automated filter -- users should treat
the flags as candidates for closer inspection.

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaFlag")
```

## Quick Start

### Flag contamination from lab blanks

``` r
library(TaxaFlag)

flagged <- flag_contaminant(
  df               = reads_long,
  taxon_col        = "taxon_name",
  reads_col        = "n_reads",
  event_col        = "event_id",
  control_samples  = c("Blank_1", "Blank_2"),
  contaminant_type = "lab_contaminant"
)

# Output adds: lab_contaminant_risk, lab_contaminant_score, lab_contaminant_reason
# Filter to high-risk taxa (probable contaminants)
flagged[flagged$lab_contaminant_risk == "high", ]
```

### Flag handler artifacts (camera traps)

``` r
flagged <- flag_handler(
  df               = camera_detections,
  datetime_col     = "datetime",
  group_col        = "camera_id",
  interval_minutes = 30
)
```

### LLM expert review

``` r
reviewed <- review_assignments(
  df         = consensus_results,
  taxon_col  = "consensus_taxon",
  context    = list(geography = "Southern California", habitat = "Marine"),
  target_group = "fish"
)
# Returns 8 structured columns:
# habitat_plausibility, geographic_plausibility, scope_plausibility,
# contamination_risk, review_alternatives, review_lower_hypotheses,
# review_confidence, review_comment

# Filter to contamination concerns
reviewed[reviewed$contamination_risk %in% c("high", "moderate"), ]
```

## Reporting

``` r
# Generate a report section for assemble_report()
section <- report_flags(flagged)
```

## Vignettes

-   [Quality Flagging](vignettes/quality-flagging.Rmd) -- full workflow
    guide

## Part of TaxaID

TaxaFlag is the final step in the TaxaID pipeline. It receives
assignments from TaxaAssign and produces quality-annotated output for
interpretation.

**Ecosystem:** TaxaAssign -\> **TaxaFlag**

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   TaxaTools (for LLM provider functions and report assembly)
-   An LLM API key is needed for `review_assignments()`

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic).
