# Positive controls in TaxaID: options, pros and cons

**Status:** design assessment only, written 2026-09-07 during package wrap-up,
revised the same day after discussion. No code was written or changed.
Companion to `REENTRY_metadata_driven_blank_detection.md` (negative controls)
and `AQUARIUM_BENCHMARK_DESIGN.md` (mock communities).

## 1. Two kinds of positive control

| | Type 1: ecological | Type 2: analytical |
|---|---|---|
| What it is | A species independently known to be present at the site (survey, capture, tag, direct observation) | Known material added to the run: DNA of a chosen species in its own control sample; a known photo in an image batch; a known recording in an acoustic batch |
| What it certifies | The sampling + assay can recover a species that is really there (sensitivity) | PCR amplified (or the classifier ran) for one or more species of interest, and how much signal leaks between samples |
| Natural unit | Site (grid x habitat), the same key the prior uses | Sample / event, a dimension the match object does not carry |
| Where it plugs in | Occurrence table (TaxaFetch) feeding the kernel prior (TaxaExpect) | Reads table (TaxaFlag); optionally likelihood calibration (TaxaLikely) |

For Type 2 the decisive design question is whether the spiked species is
**native** (could genuinely be in the field samples) or **non-native** (cannot
be). The two need different handling, and the current tooling silently does the
wrong thing for a native spike (section 4).

## 2. What exists today (verified in source, 2026-09-07)

**Stacking local occurrence data is an established pattern.**
`TaxaFetch::stack_occurrences()` row-binds any number of occurrence frames on
`decimalLatitude`/`decimalLongitude` and keeps every column.
`PtConceptionWorkflow_18S_2_single_site.R` already stacks a local survey (the
Littler data, tagged `datasource = "Littler"`) onto the GBIF pull before
`create_taxon_names()`, habitat labelling and `estimate_kernel_priors()`. The
kernel needs only taxon, lat, lon and habitat columns. A record at the site
itself gets kernel weight 1, the maximum.

**Prior scale.** `theta` is a compositional share of the local
kernel-weighted record pool, `theta_i = (c_i s + m p_i) / (n_eff + m)`. One
at-site record therefore moves a species by roughly `1 / n_eff`, which on the
production sites is hundreds to thousands of effective records. A species with
exactly one supported record becomes a singleton, and singletons define the
missing-mass estimate that prices every undetected-species prior.

**Type 1 evidence hook is narrower than stacking.**
`generate_user_specified_evidence()` feeds `apply_undetected_evidence()`, but
only for taxa with no row anywhere in the priors, and only up to the singleton
mean. A species known to be present nearly always has records, so the hook
usually does nothing for exactly this case. Stacking a record sidesteps both
limits because a record is data, not evidence.

**Type 2 leakage pass is built, species-blind.** `flag_contaminant()` accepts
`contaminant_type = "positive_control"` with `control_samples` = the
positive-control sample IDs, reusing the blank-vs-field depth-weighted ratio.
Any taxon with a higher depth-weighted rate in the control than in the field
gets `invalid_positive_control`. It does not know which species was spiked.
The Palmyra workflow (`TaxaFlag/inst/contaminant_workflow.R`) excludes the
positive controls from the extraction and PCR blank passes with
`exclude_samples` and runs the positive-control pass third.

**Pipeline order is fixed: match, flag, drop, then priors and posteriors.**
Both production workflows BLAST every column including controls, run
`flag_contaminant()` on the long reads table, filter the match object on
`validity_flag`, and only then fetch references, train and compute posteriors.
`validity_flag` is never read by TaxaAssign, TaxaLikely or TaxaMatch. The match
object has one row per `observation_id` x candidate with no sample dimension,
so a control's ASV and a field sample's ASV are the same observation; controls
must be handled on the reads table.

**Likelihood side.** `calibrate_query_noise()` estimates the
train-vs-inference score offset from a surrogate truth set
(`identify_confident_observations()`, genera where one species clears the
occurrence-prior threshold) whose selection bias its own documentation names.
The tau workflow is the only labeled-query consumer and needs a `true_species`
column the canonical match object does not carry. There is no accuracy or
log-loss function in the exported API.

## 3. Type 1 options: species known present at the site

### 1A. Stack positive-control occurrences into the occurrence table (recommended)
Build a small frame with one row per confirmed species x site (lat, lon,
taxon, `datasource = "positive_control"`, date if known), pass it through the
same name verification and habitat labelling as the survey data, and
`stack_occurrences()` it onto the GBIF pull before the kernel.
Pros: zero new code and an existing production precedent; bypasses the
evidence hook's eligibility gate and singleton ceiling honestly, because a
record is data; the record gets full kernel weight at distance 0; provenance
survives in `datasource`, so `winner_has_occurrence_record` becomes TRUE for
the right reason; the same rows serve the recovery report (1B).
Cons: one record moves theta by about `1 / n_eff`, so a single confirmation
barely changes an assignment; the only way to move it more is to stack more
rows, and the number of rows is an unprincipled knob unless they are real
survey records (one per visit or replicate, not per individual); a stacked
record for an otherwise-unrecorded species becomes a singleton and nudges the
missing-mass estimate that prices all undetected priors; if the confirmation
came from a survey that is also in GBIF, dedupe on `datasource` or it is
counted twice; undated site-level presence ignores temporal mismatch.

### 1B. Recovery report, no prior change
Run the pipeline as usual, then report for each confirmed species whether it
was detected, at what read support, and what posterior it received.
Pros: measures what an ecological control is for, sensitivity and the
false-negative rate; no circularity; reportable in a methods paper.
Cons: improves no assignment; the post-hoc join is small but new.
1A and 1B are complementary and use the same input frame.

### 1C. Existing user-specified evidence hook
Pros: zero code, documented, `p_conc` is the right place to encode certainty.
Cons: skips any species that already has a record, caps at the singleton
mean, and double counts a sighting that is also in GBIF. Dominated by 1A.

### 1D. New channel that pins the prior regardless of records
Pros: does what a user naively expects. Cons: theta is a share, not a
presence probability, so there is no principled value to pin to and raising
one share silently lowers the rest; invites circularity when the confirmation
motivated the study; contradicts the design rule that external evidence never
out-priors a detection. Not recommended.

### 1E. Route confirmation through update_prior_from_consensus()
Pros: reuses the capped, never-demote, veto-respecting soft-confirmation
machinery. Cons: that function is leave-one-out across observations in the
run, so an external pseudo-observation is a foreign object; needs code.
Only worth it if 1A's per-record increment proves too small in practice.

### 1F. Detection-probability calibration across many sites
Across sites with confirmed species, the fraction recovered estimates
p(detect | present), the quantity that separates "absent" from "present but
undetected" in the undetected-evidence mixture. Pros: the only option that
turns controls into a model parameter. Cons: needs many sites; touches the
mixture design; outside wrap-up scope.

Where Type 1 matters for assignment: only when the confirmed species sits among
congeners the marker cannot separate. A 100% match needs no prior help. In the
ambiguous case a tilt toward the confirmed species is legitimate if the
confirmation is independent of the eDNA and the sister species is not also
plausible. 1A tilts by a small, data-sized amount, which is the right size.

## 4. Type 2 options: known material in the run

### The native / non-native fork
Running a positive control through `flag_contaminant()` as a control sample
scores every taxon by its depth-weighted rate in controls versus field. A
spike is by construction the dominant taxon in its control, so the spiked
species is flagged `invalid_positive_control` and the workflow's filter drops
it from every field sample. For a **non-native** spike that is the intended
leakage screen. For a **native** spike (a species of interest that may really
be at the site) it deletes the genuine detections the control was meant to
validate. The function cannot tell the two apart.

### 2A. Non-native spike: leakage pass plus recovery check
Handle as now: exclude the control from the blank passes, run the
positive-control pass, drop the spike's reads from field samples. Add a
recovery check on the reads table: spike reads in each control above a
threshold means PCR worked. Pros: built and tested; leakage is unambiguous;
the recovery check is a one-line summary. Cons: certifies PCR for a species
nobody cares about ecologically; nothing links the leaked-read counts back to
a per-run cross-talk rate.

### 2B. Native spike: recovery check only, never a control sample
Pass the control's ID in `exclude_samples` to every `flag_contaminant()` call
(as Palmyra already does for the blank passes) and do not run the
positive-control pass. Check recovery in the control. Pros: preserves genuine
field detections; confirms PCR for the species of interest. Cons: leakage
from the spike into field samples is invisible, so a field detection of that
species could be spillover; heavy spikes leak into adjacent blanks and the
blank pass then flags the same species as a lab contaminant, deleting it
anyway, so keep spike concentration modest and check the blanks for it.

### 2C. Paired spike: non-native plus native in the same control (recommended)
Add a non-native species alongside each native spike. The non-native spike's
reads in each field sample measure that sample's leakage from the control.
Applying the same rate to the native spike's control reads gives the expected
leaked reads of the native species per field sample; field reads well above
that expectation are genuine. Pros: turns the leakage question for a native
spike into a per-sample read threshold instead of a species-wide deletion;
the non-native reads also give a per-run cross-talk (tag-jump) rate usable as
a minimum-read threshold for any low-abundance detection; all on the reads
table, no match-object change. Cons: lab design change; needs the leakage
model written down (a proportional cross-talk rate per sample is the simplest
defensible form); assumes both spikes amplify comparably.

### 2D. Species-aware positive-control check in flag_contaminant()
An `expected_taxa` argument naming the spiked species, with a native flag.
Then: confirm recovery per control; for non-native spikes flag only that
species' field reads; for native spikes apply the 2C threshold instead of
deletion; treat other taxa in the control as field-to-control bleed and report
the implied cross-talk rate. Pros: one contained change encodes the whole
native/non-native policy so workflows cannot get it wrong. Cons: code.

### 2E. Spike as a labeled query for likelihood calibration
Feed the control ASV (or known photo, known recording) into
`calibrate_query_noise()` as a genuine confident observation. Pros: replaces
part of a surrogate truth set whose bias is documented; the offset math is
unchanged; for images and recordings it is the only way to get a true labeled
query in. Cons: one to three species cannot fit the linear offset; an exotic,
well-referenced spike is exactly the "easy" case the bias note warns about;
a non-native spike's prior sits at the floor, so it tests the veto, not the
offset; a known photo or call may already be in the black-box classifier's
training set.

### 2F. End-to-end recovery check through posteriors
Run the control's observations through the full pipeline in isolation.
Pros: a per-run health check; a non-native spike correctly suppressed by the
prior is a useful manuscript figure. Cons: needs the sample dimension the
match object lacks, so it is a workflow-script exercise today.

### 2G. Mock community
Already designed in `AQUARIUM_BENCHMARK_DESIGN.md`. Real accuracy, log-loss
and TP/FP/FN, which nothing exported computes today. A project, not a per-run
control.

## 5. Recommendation for wrap-up

- **Type 1: document stacking (1A) plus the recovery report (1B).** Add a
  short note to the workflow template showing a positive-control occurrence
  frame stacked with `stack_occurrences()` and tagged by `datasource`, with
  the caveat that one record is a small nudge by design. Mention the evidence
  hook (1C) only to explain why it does not apply to recorded species.
- **Type 2: document the native / non-native fork.** Non-native: existing
  leakage pass plus a recovery check. Native: `exclude_samples` everywhere,
  never a control sample, recovery check only, watch the blanks. Recommend
  pairing a non-native spike with any native spike (2C).
- Do not add a pin-the-prior channel (1D).
- If code is reopened, the best value per line is 2D (species-aware check
  with the native flag and the 2C threshold), then 2E, then 1E.
