---
editor_options:
  markdown:
    wrap: 72
---

# TaxaFlag

Post-assignment quality flagging for the
[TaxaID](https://github.com/kdlafferty/TaxaID) ecosystem. Identifies
anomalous detections in taxonomic assignment results using data-driven
and expert-review approaches.

Taxonomic assignment matches observations to identifications, but
samples often contain artifacts and uncertainties. Evaluating thousands
of lines by eye is tedious, so TaxaFlag provides three independent
"expert-level" post-hoc checks:

-   Contamination screening compares taxon detection counts against
    control samples (lab blanks, field blanks, positive controls). For
    example, in metabarcoding, human and food-related sequences commonly
    appear, and their relative frequency in controls can justify
    removal.
-   Handler artifact detection flags observations that fall within a
    time buffer around camera setup and retrieval, when human activity
    is expected.
-   LLM expert review uses a language model to act as an "expert" to
    assess whether each assignment is plausible given the habitat and
    geographic location, flagging unusual detections for closer
    inspection. This includes contaminants that were not found screening
    blanks.

## Flagging Methods

| Method | Function | Data needed |
|------------------------|------------------------|------------------------|
| Control validation | `validate_controls()` | Detection counts + control labels (+ site, ideally) |
| Contamination | `flag_contaminant()` | Detection counts + control samples |
| Handler artifacts | `flag_handler()` | Timestamps + setup/retrieval times |
| Expert review | `review_assignments()` | Assignments + LLM API key |

Each method is independent; use one, two, or all three depending on your
data type and available metadata. Flags are additive columns, not
filters. Together, these checks target false positives that survive
upstream statistical assignment: contamination, handler artifacts,
allochthonous transport (e.g., eDNA carried by currents from outside the
sampling area), and other ecologically implausible detections.

## Methods

### Control Validation

Distinguishing controls from samples is essential for screening out
contaminants. But labeling errors can make the real community look like
contamination (and vice versa). Existing tools like `decontam` assume
the labels are correct. But `validate_controls()` tests the labels
first. If controls resemble samples (Bray-Curtis distance), the function
gives a warning.

### Contamination Scoring

Contamination occurs in many different forms. This can occur in eDNA
when handling or lab supplies introduce DNA from species not present at
the sampling site. Some of these are predictable (humans and our food
species). Field and lab blanks are often used to identify these
sequences.

TaxaID can screen out contaminant signal found disproportionately in
blanks before it enters a workflow. `flag_contaminant()` computes a
depth-weighted detection rate per taxon in each group (taxon reads /
total reads for that group, field or control), then a score:

```         
score = field_rate / (field_rate + control_rate)
```

shrunk toward 0.5 by `prior_weight` (default 20, in read-equivalent
units) so taxa with little total read support aren't scored
confidently. Scores range from 0 (taxon found only in controls) to 1
(taxon found only in field samples). Default thresholds classify scores
as `"high"`
risk (score ≤ 0.5, probable contaminant), `"moderate"` risk (0.5 \<
score ≤ 0.9, ambiguous), or `"low"` risk (score \> 0.9, likely genuine
detection). For positive controls, the interpretation inverts: taxa from
positive controls appearing in field samples indicate
cross-contamination. And a low-read taxon that never appeared in any
control is pulled down out of the `"low"` risk band.

Users should be conservative when removing signals, especially given
that control samples are usually rare (or entirely missing). Remove
observations flagged as invalid, but don't require confirmed valid to
keep the rest.

``` r
# correct
to_remove <- startsWith(flagged$validity_flag, "invalid_")
# WRONG, and much worse with the evidence gate on
to_remove <- flagged$validity_flag != "valid"
```

#### Detailed categorization

`require_control_evidence = TRUE` states what the evidence actually
supports:

| state | meaning |
|----------------------------|--------------------------------------------|
| `no_control_evidence` | never detected in a control: an honest unknown, and normally the large majority |
| `invalid_{type}` | control rate above sample rate, on at least `min_control_obs` controls, at `min_sites_systemic` or more sites. Name retained so existing `invalid_*` filters keep working |
| `insufficient_control_evidence` | in fewer than `min_control_obs` controls (default 2). Not assessable. Do not filter |
| `not_control_enriched` | in a control at or below its sample rate: signal leaking sample -> control. Do not filter |
| `single_site_enriched` | control-enriched, but at one site whose samples also carry it: local, not systemic. Do not filter |
| `questionable_{type}` | in a control, rates do not separate |

### Handler Artifact Detection

Camera traps have a particular type of contamination when cameras are
deployed and retrieved. `flag_handler()` identifies observations that
fall within a time buffer of camera setup or retrieval, when human
activity is expected. For each group (e.g., camera station), the
function identifies the earliest and latest timestamps as the
sampling-period edges. Each observation receives a linear score based on
its proximity to the nearest edge:

```         
handler_score = minutes_to_nearest_edge / interval_minutes
```

clamped to [0, 1]. The default interval is 30 minutes. Observations
outside the interval score 1.0 (valid); those at the exact edge score
0.0 (probable artifact). When `handler_taxa` is specified (e.g., "Homo
sapiens"), only those taxa are scored for temporal proximity, other
species detected near edges are assumed legitimate.

### LLM Expert Review

`review_assignments()` submits each unique taxon (in batches of 15) to
an LLM for structured assessment across eight dimensions: habitat fit,
geographic plausibility, taxonomic scope, contamination risk, plausible
alternatives, finer-rank hypotheses, confidence, and a free-text
comment. Plausibility columns use a consistent vocabulary: `"likely"` /
`"possible"` / `"unlikely"` (higher = more plausible genuine detection).
Contamination risk (independent of `flag_contaminant()`) uses `"low"` /
`"moderate"` / `"high"` (higher = more contamination risk). The function
includes truncation recovery: if an LLM response is cut off mid-JSON, it
walks backward to find the last complete object and parses what is
available. Taxa omitted by the LLM are filled with NA. Supports eDNA,
acoustic, and image data via the `data_type` param. This review is
intended as a structured second opinion, not an automated filter. Users
should treat the flags as candidates for closer inspection.

## Key Functions

Control validation and contamination:

-   `validate_controls()`: test whether samples labelled as controls
    are compositionally consistent with being controls, and whether
    any field sample looks like a control instead
-   `flag_contaminant()`: compare detection rates between field
    samples and controls and score each taxon as a probable
    contaminant, ambiguous, or likely genuine detection

Handler artifacts:

-   `flag_handler()`: flag detections that fall within a time buffer
    of camera setup or retrieval, when human handler activity is
    expected

LLM review:

-   `review_assignments()`: send each unique taxon from a consensus
    table to an LLM for structured expert review of habitat fit,
    geographic plausibility, taxonomic scope, and contamination risk,
    with suggested plausible alternatives

Spatial and watch-list checks:

-   `check_gbif_tile_range()`: download GBIF's occurrence-density map
    tiles around a query point and report how isolated that point is
    from the taxon's known range
-   `compute_local_occurrence_distance()`: for each taxon, find the
    nearest already-fetched occurrence record and report its distance
    from the query point, at no cost of a new GBIF call
-   `flag_watch_candidates()`: flag observations where a watch-list
    species outscores the consensus winner on raw match score, since a
    watch-list species' occurrence prior stays low by design and would
    not otherwise surface it
-   `review_spatial_context()`: open an interactive Shiny gadget for
    scrolling through consensus taxa by plausibility and viewing each
    flagged taxon's live GBIF occurrence-density map and spatial
    context

Reporting and cache:

-   `add_posthoc_assessment()`: append occurrence-plausibility and
    discrimination diagnostic assessments to a consensus data frame,
    reported separately for the primary and consensus taxon
-   `report_flags()`: summarize the quality flags applied by TaxaFlag
    into a report section for `assemble_report()`
-   `taxaflag_clear_cache()`: report or prune this package's cache;
    the shared signature and the cross-package
    `TaxaTools::taxaid_cache_report()` are described in the TaxaID
    README's Caching and resources section

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaFlag")
```

## Quick Start

### Check that the blanks really are blanks (do this first)

``` r
library(TaxaFlag)

checked <- validate_controls(
  input_df        = reads_long,
  event_col       = "event_id",
  taxon_col       = "ESVId",     # a fine-grained candidate/detection ID beats
  count_col       = "n_reads",   # a taxon name: it does not depend on
  control_samples = blank_ids,   # assignment having succeeded
  site_col        = "Site"       # supply this if you have it; the null is per site
)

# controls that look like field samples, and samples that look like controls
checked[checked$verdict %in% c("RESEMBLES_SAMPLE", "RESEMBLES_CONTROL"), ]

# and read the power before believing a clean result
attr(checked, "site_power")
```

### Flag contamination from lab blanks

``` r
flagged <- flag_contaminant(
  input_df               = reads_long,
  taxon_col        = "taxon_name",
  count_col        = "n_reads",
  event_col        = "event_id",
  control_samples  = c("Blank_1", "Blank_2"),
  contaminant_type = "lab_contaminant"
)

# Output adds: observation_validity, validity_flag, validity_reason
# Filter to invalid taxa (probable contaminants)
flagged[flagged$validity_flag == "invalid_lab_contaminant", ]
```

For new work, gate on evidence and use site breadth:

``` r
gated <- flag_contaminant(
  input_df                 = reads_long,
  taxon_col                = "ESVId",
  count_col                = "n_reads",
  event_col                = "event_id",
  control_samples          = blank_ids,
  require_control_evidence = TRUE,   # no verdict without a control detection
  site_col                 = "Site", # systemic vs local
  min_control_obs          = 2L     # don't condemn on ONE blank observation
)

# what to actually remove
gated[gated$validity_flag == "invalid_lab_contaminant", ]
# what NOT to remove, though the ungated path would have
gated[gated$validity_flag == "not_control_enriched", ]
# and what simply cannot be assessed
table(gated$validity_flag)
```

### Flag handler artifacts (camera traps)

``` r
flagged <- flag_handler(
  input_df               = camera_detections,
  datetime_col     = "datetime",
  group_col        = "camera_id",
  interval_minutes = 30
)
```

### LLM expert review

``` r
reviewed <- review_assignments(
  input_df         = consensus_results,
  taxon_col  = "consensus_taxon",
  context    = list(geography = "Southern California", habitat = "Marine"),
  target_group = "fish"
)
# Returns 8 structured columns (llm_-prefixed: independent LLM judgments,
# never derived from the pipeline's own values):
# llm_habitat_plausibility, llm_geographic_plausibility, llm_scope_plausibility,
# llm_contamination_risk, review_alternatives, review_lower_hypotheses,
# review_confidence, review_comment

# Filter to contamination concerns
reviewed[reviewed$llm_contamination_risk %in% c("high", "moderate"), ]
```

## Reporting

``` r
# Generate a report section for assemble_report()
section <- report_flags(flagged)
```

## Vignettes

-   [Quality Flagging](vignettes/quality-flagging.Rmd): full workflow
    guide

## Part of TaxaID

TaxaFlag is the final step in the TaxaID pipeline. It receives
assignments from TaxaAssign and produces quality-annotated output for
interpretation.

Ecosystem: TaxaAssign -\> TaxaFlag

See the [TaxaID README](https://github.com/kdlafferty/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID, A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0; R Core Team 2025)
-   TaxaTools (for LLM provider functions and report assembly)
-   An Application Programming Interface (API) key for an LLM provider
    (Anthropic Claude, Google Gemini, OpenAI, or local Ollama; see
    TaxaTools) is needed for `review_assignments()`

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic PBC, San
Francisco, California).

## References

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
