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
    inspection. This includes contaminants that were not found in
    screening blanks.

## Flagging Methods

| Method | Function | Data needed |
|------------------------|------------------------|------------------------|
| Control validation | `validate_controls()` | Detection counts + control labels (+ site, ideally) |
| Contamination | `flag_contaminant()` | Detection counts + control samples |
| Handler artifacts | `flag_handler()` | Timestamps + setup/retrieval times |
| Expert review | `review_assignments()` | Assignments + LLM API key (+ site coordinates for site-aware geography) |
| Identity and presence screen | `screen_assignments()` | Reviewed assignments (+ posterior table) |

Each method is independent; use any combination depending on your data
type and available metadata. Flags are additive columns, not filters.
Together, these checks target false positives that survive upstream
statistical assignment: contamination, handler artifacts, allochthonous
transport (e.g., eDNA carried by currents from outside the sampling
area), and other ecologically implausible detections.

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
units) so taxa with little total read support aren't scored confidently.
Scores range from 0 (taxon found only in controls) to 1 (taxon found
only in field samples). Default thresholds classify scores as `"high"`
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
| `not_control_enriched` | in a control at or below its sample rate: signal leaking sample -\> control. Do not filter |
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

By default the prompt carries no number the pipeline computed: not the
posterior, the occurrence prior, the GBIF distance or the iNaturalist
fields. A review shown the pipeline's own confidence cannot contradict it
independently, and a review shown a taxon's GBIF distance cannot catch an
error in the occurrence data. Pass the matching column names
(`consensus_posterior_col`, `winner_prior_col` and the rest) to send any of
them.

Site-aware geography
(`review_assignments(sites = , site_col = "site")`): when a study spans
a range where a taxon is plausible at some sites but not others, pass a
table of the study's sites with their latitude and longitude. For each
taxon, the LLM then says where in the study area it is plausible
(everywhere, a latitude range, or a list of unlikely sites), returned
per row as `llm_geographic_plausibility_site`. A site verdict is never
more plausible than the taxon's study-wide verdict. Without `sites`, the
review is unchanged.

### Screening reviewed assignments

`screen_assignments()` turns the review's verdicts into suggested
actions, using two separate questions.

Identity: can the assignment be trusted? This depends on how well the
best reference match fits (TaxaLikely's absolute-fit flag) and on
geography (and, for a poor fit, habitat):

| Rule | Fit | Geography | Suggested action |
|------------------|------------------|------------------|------------------|
| I1 | good | plausible | keep |
| I2 | good | unlikely | move up to a genus or family shared with a local, referenced relative that scores nearly as well; otherwise "review", suggested exclude |
| I3 | poor | plausible | move up one rank (genus and species calls only); coarser calls are kept with `poor_fit_flag` |
|  | poor | plausible, habitat unlikely | exclude (family or finer) |
| I4 | poor | unlikely | exclude |

Because TaxaFlag was designed with eDNA in mind, it separates out the
presence of a sequence at a location from the presence of an organism
that produced the sequence. Sequences often "bleed" across habitats,
thus an assignment to a sequence may be correct even if the taxon does
not occur where the sample was taken. After the identity of a sequence
is determined, it then becomes relevant to assess if the organism that
produced the sequence is likely at the location. Often this
determination comes down to appropriate habitat.

Presence: does the organism live at the collection site? This depends on
habitat and scope only, and never excludes a row by itself:
`"resident"`, `"off_habitat"` (e.g., DNA carried from elsewhere), or
`"out_of_scope"`. Reports filtered by habitat or scope use it.

Every input row (likely or unlikely) is returned, in order, with
`identity_action`, `identity_taxon_after`, `identity_rank_after`,
`identity_reason`, `suggested_action`, `presence` and `poor_fit_flag`
appended. Filtering out unlikely consensus assignments is a separate,
deliberate step, and an expert's own keep or exclude list should
override it. With
`screen_assignments(geography_col = "llm_geographic_plausibility_site")`
the rules judge each taxon at each site. With
`screen_assignments(blank_flag_col = )`, rows with blank (contamination)
evidence also suggest exclude. `relative_score_gap = 0.25`, the margin
for rule I2, is a chosen value, not calibrated; the screen reports how
many rows each rule acted on.

### Overriding a per-site verdict with local records

A per-taxon geographic rule can name one latitude bound, and the bound can
arrive on the wrong side: a southern range limit written as `lat_max` puts
every northern site outside the band. The reviewer's own study-wide verdict
then says `"likely"` while the per-site verdict says `"unlikely"` at every
site the taxon was actually detected at. Nothing inside TaxaFlag can tell
that apart from a correct exclusion, because the question is empirical --
is the taxon recorded near this site? -- and TaxaFlag holds no occurrence
data.

So the override belongs in the workflow, which already has the occurrence
records and the site table, and it is passed in as a column. The shape
below keeps the evidence visible rather than quietly rewriting a verdict.

``` r
# Thresholds are yours to measure on your own data, not constants to copy:
# a minimum count high enough that one or two records (or a single
# misidentification) cannot rescue a row, and a radius with a reason --
# here the prior kernel's calibrated lambda_km.
RECORDS_MIN <- 3L
RECORDS_KM  <- 50

# Great-circle km. TaxaFlag has no "count records within a radius" helper:
# compute_local_occurrence_distance() returns the distance to the NEAREST
# record, which is a different question -- one close record is not evidence
# of an established population.
.km <- function(lat1, lon1, lat2, lon2) {
  r <- pi / 180
  a <- sin((lat2 - lat1) * r / 2)^2 +
    cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2
  12742 * asin(pmin(1, sqrt(a)))
}

# Only rows the per-site verdict calls unlikely are even asked about.
ask <- unique(reviewed[reviewed$llm_geographic_plausibility_site %in% "unlikely" &
                         !is.na(reviewed$consensus_taxon),
                       c("consensus_taxon", "consensus_rank", "Site")])

ask$geo_local_record_location_n <- vapply(seq_len(nrow(ask)), function(i) {
  rank_col <- if (ask$consensus_rank[i] == "species") "taxon_name" else ask$consensus_rank[i]
  if (!rank_col %in% names(occurrences)) return(0L)
  o <- occurrences[occurrences[[rank_col]] %in% ask$consensus_taxon[i], ]
  s <- site_table[site_table$Site == ask$Site[i], ]
  stopifnot("one site-table row per Site" = nrow(s) == 1)
  km <- .km(s$lat, s$lon, o$decimalLatitude, o$decimalLongitude)
  length(unique(o$point_id[km <= RECORDS_KM]))
}, integer(1))

reviewed <- dplyr::left_join(reviewed, ask,
                             by = c("consensus_taxon", "consensus_rank", "Site"))
# A join that adds a column is only a lookup when the right side is unique
# on the key. Assert it, or a duplicate key multiplies rows silently.
stopifnot(nrow(reviewed) == nrow(.reviewed_before_join))

reviewed$geo_unlikely_overridden_by_records <-
  reviewed$llm_geographic_plausibility_site %in% "unlikely" &
  !is.na(reviewed$geo_local_record_location_n) &
  reviewed$geo_local_record_location_n >= RECORDS_MIN &
  reviewed$llm_geographic_plausibility %in% c("likely", "possible")

# The adjusted verdict lives in its own column. The screen reads this one;
# the reviewer's own column is never written to.
reviewed$geo_site_for_screen <- ifelse(
  reviewed$geo_unlikely_overridden_by_records,
  reviewed$llm_geographic_plausibility,
  reviewed$llm_geographic_plausibility_site
)

screened <- TaxaFlag::screen_assignments(
  reviewed, posterior_df = post,
  geography_col = "geo_site_for_screen"
)
```

Four columns, each doing one job:

| Column | Role |
|--------|------|
| `llm_geographic_plausibility_site` | the reviewer's own per-site verdict, never written to |
| `geo_local_record_location_n` | distinct record locations within the radius |
| `geo_unlikely_overridden_by_records` | whether the override fired, and so the audit trail |
| `geo_site_for_screen` | the adjusted verdict the screen reads |

Three properties worth keeping if you adapt this:

- **`NA` and `0` mean different things.** `geo_local_record_location_n` is
  `NA` for a row that was never asked about, and `0` for a row that was
  asked and had no records nearby. Flattening `NA` to `0` destroys that
  distinction, and "not evaluated" then reads as "no evidence found".
- **The override can only relax an exclusion, never create one.** It moves
  a verdict from `"unlikely"` toward the study-wide `"likely"` or
  `"possible"` and never the other way, so it cannot introduce a new false
  exclusion. Its risk runs the other way: a genuinely absent taxon kept
  because records happen to sit nearby.
- **Keep the model's own verdict.** Overwriting
  `llm_geographic_plausibility_site` in place would leave nothing able to
  tell a model verdict from an overridden one, and a report built on it
  could not describe what it had done.

## Key Functions

Control validation and contamination:

-   `validate_controls()`: test whether samples labelled as controls are
    compositionally consistent with being controls, and whether any
    field sample looks like a control instead
-   `flag_contaminant()`: compare detection rates between field samples
    and controls and score each taxon as a probable contaminant,
    ambiguous, or likely genuine detection
-   `flag_hopped_detections()`: flag detections a sequencing run's own
    read spillover explains, from the run's control samples or its spike
    taxa, and report the spillover rate it fitted for each run

Sequencing-run and sample checks:

-   `flag_failed_libraries()`: flag libraries and whole runs that failed
    to sequence, reading the same extract's other markers as the control
-   `classify_sample_identity()`: gate each sample on whether its
    composition looks like the label it carries, so a mislabelled blank
    or a swapped tube is caught before it is used as a control
-   `review_sample_identity()`: send the samples that do not look like
    their label to an LLM for a second opinion, with the run's spike-in
    taxa in the prompt

Handler artifacts:

-   `flag_handler()`: flag detections that fall within a time buffer of
    camera setup or retrieval, when human handler activity is expected

LLM review:

-   `review_assignments()`: send each unique taxon from a consensus
    table to an LLM for structured expert review of habitat fit,
    geographic plausibility, taxonomic scope, and contamination risk,
    with suggested plausible alternatives. The review is advisory: its
    ratings are columns and it never removes a row, so a verdict cannot
    silently shorten a species list and an expert keeps the decision. A
    workflow can derive a single flag from those verdicts -- the
    TaxaWizard template does, as `llm_review_flag` -- but this function
    does not write one. `poor_absolute_fit_col` and `best_identity_col` carry
    TaxaLikely's absolute-fit signal into the prompt (both default to
    the column names TaxaLikely emits; `NULL` disables either), so the
    reviewer is told, with the identity, when even the best raw match
    reaches no rank's marker-specific threshold -- which makes the name
    uncertain at the called rank, but is not by itself grounds for an
    "unlikely" habitat, geography or scope rating. The default `llm_fn` calls
    `TaxaTools::call_api()` and sends no temperature at all, keeping the
    provider's own default, because some current models reject that
    parameter. The site context combines the analyst's own wording with
    an ecoregion synthesised from the site table, so the reviewer is
    told where the samples came from rather than inferring it from the
    taxon names. A call whose name came from the local records rather
    than from the sequence is marked as such, since judging it as a
    sequence match would ask the reviewer the wrong question

-   `screen_assignments()`: suggested keep, move-up or exclude actions
    from the review's verdicts and the match's absolute fit, plus a
    presence label (resident, off-habitat, out of scope). Flags only;
    see *Screening reviewed assignments* above

-   `flag_backbone_conflicts()`: report names whose own backbone
    placement disagrees with itself -- one name carried at more than one
    rank, or under more than one parent at the same rank -- learned from
    the backbone present in the data rather than from any list of taxa.
    The inverse, many names for one organism, is invisible to it by
    construction, so zero conflicts says nothing about synonymy

Spatial and watch-list checks:

-   `check_gbif_tile_range()`: download GBIF's occurrence-density map
    tiles around a query point and report how isolated that point is
    from the taxon's known range. `cache_dir` keeps one entry per key so
    a re-run asks GBIF nothing twice; a verdict built on a tile that
    could not be fetched carries `attr(x, "tile_fetch_failed") = TRUE`
    and is never cached, so a failure is not served later as a range
-   `compute_local_occurrence_distance()`: for each taxon, find the
    nearest already-fetched occurrence record and report its distance
    from the query point, at no cost of a new GBIF call
-   `flag_watch_candidates()`: flag observations where a watch-list
    species outscores the consensus winner on raw match score, since a
    watch-list species' occurrence prior stays low by design and would
    not otherwise surface it
-   `review_spatial_context()`: open an interactive Shiny gadget for
    scrolling through consensus taxa by plausibility and viewing each
    flagged taxon's live GBIF occurrence-density map and spatial context

Reporting and cache:

-   `add_posthoc_assessment()`: append occurrence-plausibility and
    discrimination diagnostic assessments to a consensus data frame,
    reported separately for the primary and consensus taxon
-   `report_flags()`: summarize the quality flags applied by TaxaFlag
    into a report section for `assemble_report()`
-   `taxaflag_clear_cache()`: report or prune this package's cache; the
    shared signature and the cross-package
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

# Site-aware geography: one verdict per taxon per site
reviewed <- review_assignments(
  input_df     = consensus_results,
  taxon_col    = "consensus_taxon",
  context      = list(geography = "Pacific coast", habitat = "Marine"),
  target_group = "fish",
  sites        = site_table,          # columns: site, lat, lon
  site_col     = "site"
)

# Suggested actions; nothing is dropped
screened <- screen_assignments(
  reviewed,
  posterior_df  = posteriors,
  geography_col = "llm_geographic_plausibility_site"
)
table(screened$suggested_action, screened$presence, useNA = "ifany")
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

Lafferty, K.D., TaxaID: A modular R ecosystem for Bayesian taxonomic
assignment: U.S. Geological Survey software, provisional release, not
yet citable. <https://github.com/kdlafferty/TaxaID>

A citable version with a DOI will be released through the USGS software
release process.

## Software Requirements

-   R (\>= 4.1.0; R Core Team 2025)
-   TaxaTools (for LLM provider functions and report assembly)
-   An Application Programming Interface (API) key for an LLM provider
    (Anthropic Claude, Google Gemini, OpenAI, or local Ollama; see
    TaxaTools) is needed for `review_assignments()`

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with Claude Code (Anthropic PBC, San Francisco, California).

## References

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
