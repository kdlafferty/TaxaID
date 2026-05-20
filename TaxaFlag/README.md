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
filters.

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
  df              = assignments,
  taxon_col       = "consensus_taxon",
  reads_col       = "reads",
  event_col       = "event_id",
  control_samples = c("Blank_1", "Blank_2"),
  contaminant_type = "lab_blank"
)

# Inspect flagged taxa
flagged[flagged$flag_contaminant == TRUE, ]
```

### Flag handler artifacts (camera traps)

``` r
flagged <- flag_handler(
  df              = camera_detections,
  datetime_col    = "datetime",
  group_col       = "camera_id",
  interval_minutes = 30
)
```

### LLM expert review

``` r
reviewed <- review_assignments(
  df         = consensus_results,
  taxon_col  = "consensus_taxon",
  context    = list(main_habitat = "Marine", region = "Southern California")
)
# Returns 8 structured columns: habitat_fit, geographic_plausibility,
# scope_flag, contaminant_flag, alternatives, lower_hypotheses,
# confidence, comment
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
