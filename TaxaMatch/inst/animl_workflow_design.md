# Animl + TaxaID Workflow Design

*Discussion document for colleagues using Animl camera trap image classification.*
*Last updated: 2026-06-24*

---

## Where TaxaID Fits

A typical camera trap workflow moves through three stages:

1. **Detection and classification** — Animl (MegaDetector + SpeciesNet) identifies
   animals in images and assigns species labels with confidence scores.
2. **Assignment** — TaxaID converts those labels and scores into calibrated
   probabilistic species assignments. *This is where TaxaID lives.*
3. **Ecological analysis** — cameratrappr, Distance, or occupancy models use the
   per-image species assignments to estimate detection rates, abundance, and occupancy.

TaxaID does not replace Animl. It picks up Animl's output and asks: given what the
classifier said *and* what we know about which species live at this site, what is the
probability that this image shows species X?

---

## Why Probabilistic Assignments?

Animl's SpeciesNet model returns a confidence score, but that score is not a
probability of species identity. A score of 0.85 does not mean "85% chance this is
a coyote" — it means the model's output layer was high for coyote, relative to other
classes the model has seen. Two problems arise:

- **Rare but locally absent species** can score high if they look like a common one.
  A classifier trained globally may confidently call a domestic dog a wolf at a site
  where wolves have been absent for 100 years.
- **Species the model has never seen** receive no score at all, even if they are
  locally common.

TaxaID addresses both by combining classifier scores (the likelihood) with occurrence
data (the prior) in a Bayesian framework, producing a posterior probability for each
candidate species.

---

## Proposed Workflow

### Step 0 — Run Animl

In R, using the `animl` package (CRAN). MegaDetector detects animals; SpeciesNet
classifies to species. Standard Animl outputs: one CSV per batch with `FileName`,
`prediction`, `confidence`, and optionally bounding box columns.

### Step 1 — Ingest with TaxaMatch

```r
library(TaxaMatch)

match_df <- read_animl_output(
  "animl_results/",
  min_confidence = 0.1
) |>
  subset(!species %in% c("empty", "human", "vehicle"))
```

`read_animl_output()` handles long- and wide-format exports, maps column names, and
attaches an `observation_id` (image filename stem) that links every downstream result
back to the original image file.

### Step 2 — Split into Two Streams

| Stream | Criterion | Example |
|--------|-----------|---------|
| **A — Confirmed species** | High confidence, species-level prediction | `prediction = "Canis latrans"`, `confidence = 0.87` |
| **B — Unconfirmed / "Animal"** | Low confidence or coarse SpeciesNet fallback label | `prediction = "Animal"`, `confidence = 0.43` |

*(The exact split criterion depends on your Animl configuration — see Questions below.)*

### Step 3 — Stream A: Likelihood Pipeline

Standard TaxaID scoring for confident species-level predictions:

```
standardize_match_data()
  → convert_taxonomy_backbone()   # harmonize to GBIF taxonomy
  → fill_higher_ranks()           # fill genus/family from species name
  → unreferenced_candidates()     # add species Animl has never seen
  → assign_scores()               # convert confidence to likelihoods
  → join_priors()                 # attach occurrence-based priors
  → compute_posterior()           # Bayesian posterior per candidate
```

Priors come from occurrence data (TaxaExpect, GBIF) weighted by habitat and site.
Species that the classifier has never seen but that are locally expected will receive
placeholder likelihood scores and compete on the strength of their prior.

### Step 4 — Stream B: Three Options

When SpeciesNet returns "Animal" or a genus-level fallback, you have three options.
Which is best depends on your team's priorities and the answers to the questions below.

**Option B1 — Re-score with iNaturalist CV**
Submit the image file to the iNaturalist computer vision API via `score_image_inat()`.
iNat's model covers 100,000+ taxa versus SpeciesNet's ~1,300 species. Returns a ranked
list of species candidates that re-enter Stream A.

```r
# Re-score unconfirmed images via iNat CV
inat_df <- score_image_inat(
  unconfirmed_files,            # vector of image paths from Stream B
  lat = 34.10, lng = -119.07,
  observed_on = "2024-09-15"
)
# inat_df is already a match object — feeds directly into Step 3
```

**Option B2 — Manual review**
Flag Stream B images for human inspection. A reviewer upgrades "Animal" to a species
label. The reviewed label re-enters Stream A as a confirmed species. Most appropriate
when image quality is high and staff time is available.

**Option B3 — Prior-only**
Carry "Animal" images forward with no species-level likelihood. The posterior is
driven entirely by occurrence priors — equivalent to asking "given that an animal was
detected at this site, what is the most likely species?". Least informative but
requires no extra work.

### Step 5 — Merge and Finalize

```
posterior_consensus()   # merge Stream A and B outputs
                        # one row per image × candidate, with posterior probability
```

### Step 6 — Downstream Analysis

Pass the posterior table to cameratrappr (detection rates, activity patterns) or
occupancy/abundance models (Distance, unmarked). TaxaMatch's `observation_id` links
every posterior row back to the original image filename for review.

---

## What TaxaID Adds over Raw Animl Output

| Raw Animl | With TaxaID |
|-----------|-------------|
| Single best species + confidence score | Full posterior distribution over candidate species |
| Confidence score (not a probability) | Calibrated posterior probability |
| No adjustment for local species pool | Occurrence priors downweight locally absent species |
| No path for unseen species | Unreferenced species hypotheses compete on priors |
| "Animal" cases are discarded or ignored | Principled options: re-score, review, or prior-only |

---

## Questions for Colleagues

Before implementing, we need to understand how your Animl setup works. Answers to
these questions will determine which options above are feasible and how to configure
the ingest step.

**1. Column structure of your Animl CSV export**

What column(s) distinguish a confirmed (human-reviewed) assignment from an
unconfirmed (model-only) one? Specifically:

- Is there a `confirmed`, `human_label`, `reviewed`, `status`, or similar column
  that marks images a human has checked?
- Or is the confirmed/unconfirmed distinction based on confidence score alone
  (e.g., `confidence >= 0.8` → confirmed)?
- Do you use Animl's built-in review interface, or a separate review step in
  Timelapse or another tool?

**2. The "Animal" label**

When SpeciesNet returns its coarse fallback label "Animal":

- Is "Animal" always the only prediction for that image (i.e., no species-level
  candidates alongside it), or can it appear alongside species-level scores?
- What confidence value is typically attached to "Animal" predictions?

**3. Sequence classification**

Do you use Animl's `sequence_classification()` step, which refines predictions
across consecutive images in a burst? If so:

- Does this step add columns to the CSV (e.g., `sequence_id`, `sequence_label`)?
- Which label should we use — the single-image prediction or the
  sequence-refined label?

**4. Reference images**

Do you have any images of known species that were run through Animl — for example,
photos taken alongside physical voucher specimens, or images from camera traps where
a species was independently confirmed? These would be used to calibrate the likelihood
model in TaxaLikely (training the score-to-probability mapping). Even a small set
(20–50 images per species) would help.

**5. Confidence threshold**

What confidence threshold do you currently apply when accepting a SpeciesNet
prediction as a species-level identification? (The default `read_animl_output()`
minimum is 0.5, but this can be adjusted.)

**6. Location and date metadata**

- Is GPS or location metadata stored per image (EXIF or CSV column)?
- Is survey date available per image?
- If so, what format and column name?

Location and date enable TaxaID to use geographic occurrence priors
(e.g., species currently in range vs. not), which substantially improves
assignment accuracy for species with overlapping appearances.

---

*Questions or comments: contact the TaxaID development team.*
*Full package documentation: https://github.com/DOI-USGS/TaxaID*
