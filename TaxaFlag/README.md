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
samples often contain artifacts and uncertainties. TaxaFlag provides
three independent post-hoc checks:

-   **Contamination screening** compares taxon detection counts against
    control samples (lab blanks, field blanks, positive controls). For
    example, in metabarcoding, human and food-related sequences commonly
    appear, and their relative frequency in controls can justify
    removal.
-   **Handler artifact detection** flags observations that fall within a
    time buffer around camera setup and retrieval, when human activity
    is expected.
-   **LLM expert review** uses a language model to assess whether each
    assignment is plausible given the habitat and geographic location,
    flagging unusual detections for closer inspection. This includes
    contaminants that were not found screening blanks.

## Flagging Methods

| Method | Function | Data needed |
|------------------------|------------------------|------------------------|
| **Control validation** | `validate_controls()` | Detection counts + control labels (+ site, ideally) |
| **Contamination** | `flag_contaminant()` | Detection counts + control samples |
| **Handler artifacts** | `flag_handler()` | Timestamps + setup/retrieval times |
| **Expert review** | `review_assignments()` | Assignments + LLM API key |

Each method is independent; use one, two, or all three depending on your
data type and available metadata. Flags are additive columns, not
filters. Together, these checks target false positives that survive
upstream statistical assignment: contamination, handler artifacts,
allochthonous transport (e.g., eDNA carried by currents from outside the
sampling area), and other ecologically implausible detections.

## Methods

### Control Validation

**Do this before contamination screening, not after.** A field sample
mislabelled as a blank makes the real community look like contamination, so
`flag_contaminant()` then filters genuine signal. Nothing conventional checks
this: `decontam` assumes the labels are correct, and its frequency method needs
DNA concentration that many eDNA workflows do not record.

`validate_controls()` tests the labels on the principle that **a control is
defined by what it LACKS, not by what it contains.** Whatever the medium --
tapwater, sterilised seawater, molecular-grade water -- a control's defining
property is that its composition is not drawn from the sampled habitat. So the
test uses **no taxonomy at all**: it compares each control's median Bray-Curtis
distance to the field samples it sits with, against the null distribution of
sample-to-sample distance *at that same site*.

The reference must come from the data. On one real COI study the within-site
sample-vs-sample median ranged from **0.145 to 0.890 across sites in that single
dataset**, so any fixed cutoff would be simultaneously too strict and too loose
within one run. Drawing the null from each site's own samples self-calibrates to
sampling method, habitat and sampling design.

It is **two-sided**, because mislabelling runs both ways:

| verdict | meaning |
|-----------------------------|----------------------------------------------|
| `consistent_with_control` | outside the sample null, as a blank should be |
| `RESEMBLES_SAMPLE` | a control inside the sample null -- possibly a mislabelled sample |
| `consistent_with_sample` | an ordinary field sample |
| `RESEMBLES_CONTROL` | a sample that is an outlier *and* closer to the controls |
| `untestable` | the site cannot form a null |
| `untestable_no_headroom` | the null reaches the metric's ceiling, so nothing can exceed it |

**Power is reported, not assumed.** A site with many samples and a tight null
gives a real negative result; a site with two samples, or a null spanning most of
the range, has no power at all -- and both would otherwise print as "nothing
flagged". Every site carries its null, its pair count, its spread and a `power`
verdict, and each row carries a `confidence` derived from it. If *every* testable
control resembles a sample, the function warns that the control set is
compromised rather than returning a verdict list.

### Contamination Scoring

TaxaID can screen out contaminant signal found disproportionately in blanks
before it enters a workflow. Specifically,
`flag_contaminant()` compares the relative abundance of each taxon in
field samples versus control samples. Within each sample, read counts
are first converted to proportions (reads for taxon / total reads),
normalizing for sequencing depth. Proportions are then averaged across
field and control replicates, and a score is computed:

```         
score = mean_prop_field / (mean_prop_field + mean_prop_control)
```

Scores range from 0 (taxon found only in controls) to 1 (taxon found
only in field samples). Default thresholds classify scores as `"high"` risk
(score ≤ 0.5, probable contaminant), `"moderate"` risk (0.5 \< score ≤ 0.9,
ambiguous), or `"low"` risk (score \> 0.9, likely genuine detection). For
positive controls, the interpretation inverts: taxa from positive controls
appearing in field samples indicate cross-contamination.

**The score is SHRUNK, so a taxon absent from controls does NOT receive 1.0**, and
this matters more than it sounds. Because the shrinkage is measured in reads, a
low-read taxon that never appeared in any control is still pulled down out of the
`"low"` risk band. Measured on a real 12S run: of 13,597 ESVs **only 43 were ever
detected in a single control**, yet 10,300 were labelled
`questionable_lab_contaminant` -- the entire middle tier had *no control evidence
whatsoever*, and the same 75-81% rate appeared in every marker and workflow
checked, because it reflects the read-depth distribution rather than
contamination. The taxa it surfaced were the study's own target community
(*Sardinops sagax*, *Engraulis mordax*, *Clinocottus recalvus* -- a tidepool
sculpin), while the genuine contaminants were a rounding error beside them.

#### Never filter on `validity_flag != "valid"`

A fragile idiom before, and **catastrophic** under
`require_control_evidence = TRUE`. The honest-unknown state
`no_control_evidence` is not `"valid"`, and it is normally the overwhelming
majority -- on a real 12S run 16,695 of 16,826 ESVs (99.2%), on COI 32,162 of
34,899 (92.2%). A `!= "valid"` filter would delete nearly the entire dataset.
`not_control_enriched` and `single_site_enriched` are also not `"valid"`, and they
exist precisely to mean *do not remove this*. Nor is
`insufficient_control_evidence`, which means the question was not answerable.

``` r
# correct
to_remove <- startsWith(flagged$validity_flag, "invalid_")
# WRONG, and much worse with the evidence gate on
to_remove <- flagged$validity_flag != "valid"
```

#### Evidence-gated states, and site breadth

`require_control_evidence = TRUE` replaces the score bands with states that say
what the evidence actually supports:

| state | meaning |
|-----------------------------|----------------------------------------------|
| `no_control_evidence` | never detected in a control -- an honest unknown, and normally the large majority |
| `invalid_{type}` | control rate **above** sample rate, on at least `min_control_obs` controls, at `min_sites_systemic` or more sites. Name retained so existing `invalid_*` filters keep working |
| `insufficient_control_evidence` | in fewer than `min_control_obs` controls (default 2). Not assessable. **Do not filter** |
| `not_control_enriched` | in a control at or **below** its sample rate: signal leaking sample → control. **Do not filter** |
| `single_site_enriched` | control-enriched, but at one site whose samples also carry it: local, not systemic. **Do not filter** |
| `questionable_{type}` | in a control, rates do not separate |

**Direction is the point.** Contamination flows control → sample; the reverse flow
is what happens when a blank picks up a little of an abundant local taxon. A
symmetric score cannot tell them apart, and `not_control_enriched` is the state the
score-band design could not express.

**Two states rather than one, deliberately.** `not_control_enriched` and
`single_site_enriched` make *opposite* claims about enrichment -- one is not
enriched in controls, the other is enriched but only at one site -- so a single
name covering both would be false for whichever case it was not written for.
Neither asserts a direction of travel, because a rate comparison cannot establish
one.

**The evidence floor, and the limitation behind it.** The direction test is a bare
rate inequality, so rates built on one observation are not comparable to rates
built on hundreds: with 91 controls against 1,052 samples, one stray read in one
blank scores 1/91 = 0.011 and outvotes two genuine detections at 2/1052 = 0.0019.
On a real archive 55-63 per cent of everything the gate condemned rested on a
single control observation, and that tail contained genuine organisms -- a tidepool
sculpin, two red macroalgae, a sand dollar. `min_control_obs` (default 2) refuses
to condemn on one observation. A one-sided significance test with a
multiple-testing correction is the principled replacement and is **not
implemented**; `min_control_obs = 1L` restores the unfloored behaviour.

**Useful check before trusting the tier:** a genuine contaminant usually appears in
**no field sample at all**. On real data 85-97 per cent of removals had
`n_field_present == 0`. Inspect the names, and check at family level rather than
the finest candidate level (ESV/ASV for sequence data) if a downstream step
consumes families.

Supplying `site_col` adds `site_breadth_control`, `site_breadth_sample` and
`control_sites_shared`, and uses site multiplicity as a **discriminant rather
than merely as extra power**: a systemic contaminant (reagent, water supply)
appears in controls at many sites regardless of which sites' samples carry it,
whereas a local source appears in controls at the one site whose samples are full
of it. A control-enriched taxon confined to a single site that also has it in
samples is downgraded to `single_site_enriched`.

This dissolves a real dilemma rather than picking a side. Pooling controls buys
power but lets one trip's contamination speak for another's; pairing controls by
event buys specificity at the cost of power -- on real data, event-paired controls
emptied the `invalid` tier completely (0 ESVs, against 43 and 323 in pooled runs),
so the only tier resting on evidence vanished. Using the cross-site *pattern*
keeps both.

### Handler Artifact Detection

`flag_handler()` identifies observations that fall within a time buffer
of camera setup or retrieval, when human activity is expected. For each
group (e.g., camera station), the function identifies the earliest and
latest timestamps as the sampling-period edges. Each observation
receives a linear score based on its proximity to the nearest edge:

```         
handler_score = minutes_to_nearest_edge / interval_minutes
```

clamped to [0, 1]. The default interval is 30 minutes. Observations
outside the interval score 1.0 (valid); those at the exact edge score
0.0 (probable artifact). When `handler_taxa` is specified (e.g., "Homo
sapiens"), only those taxa are scored for temporal proximity -- other
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
intended as a structured second opinion, not an automated filter --
users should treat the flags as candidates for closer inspection.

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

-   R (\>= 4.1.0; R Core Team 2025)
-   TaxaTools (for LLM provider functions and report assembly)
-   An Application Programming Interface (API) key for an LLM provider
    (Anthropic Claude, Google Gemini, OpenAI, or local Ollama -- see
    TaxaTools) is needed for `review_assignments()`

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic PBC, San
Francisco, California).

## References

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
