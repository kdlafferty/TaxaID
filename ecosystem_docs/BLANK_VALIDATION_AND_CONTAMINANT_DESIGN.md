# Blank validation and contaminant filtering: the general design

Status: DESIGN, not built. Written 2026-09-20 after the PtCon/CalIntertidal
investigation, which is treated here only as a worked example.

## The principle the three questions share

**A blank is defined by what it LACKS, not by what it contains.**

Whatever the medium -- tapwater, sterilised seawater, molecular-grade water, air --
the defining property of a control is that its composition is NOT drawn from the
sampled habitat. Every rule below follows from that, and none of them needs to know
the marker, the habitat, the blank medium, or any taxon name.

The corollary is the design constraint: **every reference distribution must be
computed from the data at hand, never from a constant.** A threshold that works for
12S in a kelp forest will not work for COI in an estuary. A threshold derived from
this run's own samples adapts automatically.

---

## Q1. Is a column labelled "blank" actually a blank?

### The test
For each control, ask whether its composition is an OUTLIER relative to the
variation among the FIELD SAMPLES IT SITS WITH (same site, same event).

    null distribution  : d(sample_i, sample_j) for all sample pairs at that site
    test statistic     : median d(control, sample_k) over the site's samples
    verdict            : control is consistent with a blank if its statistic lies
                         ABOVE the null's upper region

This is compositional distance only (Bray-Curtis or Jaccard on relative abundance).
**No taxonomy is used at any point**, so it is marker-independent by construction,
and because the null comes from the site's own samples it is location- and
medium-independent too.

### Why the reference must be within-site
Within-site heterogeneity varies enormously and swamps any fixed cutoff. Measured on
COI here: sample-vs-sample median ranged from 0.145 (Valley, Santa Cruz I.) to 0.890
(Davenport Landing) ACROSS SITES IN ONE STUDY. A fixed threshold of, say, 0.8 would
call every Valley control a blank and every Davenport control a sample, on data where
both are in fact fine.

### It must be two-sided
Mislabelling runs both ways. The same machinery answers both:
  - control whose statistic falls INSIDE the sample null  -> may be a mislabelled SAMPLE
  - sample that is an outlier from the sample cloud AND close to the controls
    -> may be a mislabelled BLANK
Report both. A one-directional check silently keeps mislabelled samples in the
control set, which is the failure that corrupts everything downstream.

### It must report its own power
Two situations produce "no flags" for opposite reasons, and they must not look alike:
  - a site with 20 samples and a tight null -> a real, powerful negative result
  - a site with 2 samples, or a null so wide it spans [0.13, 1.00] -> NO POWER
Emit n_samples, the null's spread, and an explicit `power` verdict per site. A site
that cannot test its controls should say so rather than pass them.

### Degradation
  - 1 sample at a site      -> no null; fall back to the pooled across-site null and
                               say that is what happened
  - no controls at all      -> return `unassessed`, never `clean`
  - ALL controls look like samples -> do NOT emit a contaminant list. The control set
                               is compromised; that is an error condition, not a result

---

## Q2. Which ESVs deserve to be filtered?

### The defect this replaces
The current `flag_contaminant()` collapses to one shrunken score and cuts it at
`score_thresholds = c(0.5, 0.9)`. Because the score is shrunk toward a prior
(`prior_weight = 20`), LOW READ COUNT -- not blank evidence -- decides which side of
0.5 an ESV lands on. Measured: of 13,597 ESVs, **only 43 were ever detected in a
single control**, yet 10,300 were labelled `questionable_lab_contaminant`. The entire
questionable tier has NO BLANK EVIDENCE. The rate is ~75-81% in every marker and
workflow measured, because it is a property of the read-depth distribution rather
than of contamination.

### The fix: an evidence gate, then a direction, then a breadth
**Never assign a contaminant label to an ESV with zero control observations.** Output
a state, not a score band:

    no_evidence    seen in 0 controls. Cannot be assessed. (Expected to be the large
                   majority. This is an honest "unknown", not a weak "suspect".)
    contaminant    present in controls at a rate ABOVE its rate in samples
    carryover      present in controls at or BELOW its sample rate -- the blank caught
                   a little of the local community. DO NOT FILTER: this is real signal
                   leaking into the control, the opposite direction of travel.
    ambiguous      present in controls, rates statistically indistinguishable

The `carryover` state is the one the current design cannot express, and it is exactly
what makes an abundant local taxon look like a contaminant.

### Direction is the whole game
Contamination flows blank -> sample; carryover flows sample -> blank. The statistic
must be directional (rate in controls vs rate in samples, with the comparison's
uncertainty), not a symmetric "how associated is this ESV with controls".

### Carry the evidence, not just the verdict
Every row must ship `n_controls_present`, `n_controls_total`, `n_samples_present`,
and the two rates. A verdict without its evidence cannot be audited, and it is what
let a 75% flag rate sit unexamined across several workflows.

---

## Q3. What does more than one site with blanks buy?

**Site multiplicity is a DISCRIMINANT, not merely extra power.** This is the part the
multi-site design uniquely enables, and it dissolves the pooling-vs-pairing dilemma.

    a SYSTEMIC contaminant (reagent, water supply, lab surface) appears in controls at
        MANY sites, and its presence does not track which sites' samples contain it

    a CARRYOVER appears in controls at the ONE site whose samples are full of it

So for each ESV compare two breadths:

    site_breadth_control = # sites where the ESV appears in >=1 control
    site_breadth_sample  = # sites where the ESV appears in >=1 sample
    concordance          = do the control-sites coincide with the sample-sites?

    broad in controls, independent of sample-sites  -> SYSTEMIC. Filter with confidence.
    narrow in controls, concentrated where samples have it -> CARRYOVER. Keep.

This resolves the tension that currently forces a choice. Pairing blanks by event
gives specificity but destroys power -- measured here, event-pairing emptied the
`invalid` tier entirely (0 ESVs, against 43 and 323 in pooled single-site runs), so
the only tier resting on real evidence vanished. Pooling gives power but lets one
trip's contamination speak for another's. **Using the cross-site PATTERN keeps both:**
evidence is pooled across sites, while the site structure itself carries the
discriminating information.

It also degrades honestly: with one site, `site_breadth_control` is always 1 and the
discriminant is simply unavailable -- report that, and fall back to Q2 alone.

---

## What this does NOT require

No taxon list. No habitat model. No marker-specific tuning. No assumption about the
blank medium. Those were the constraints, and the design meets them because every
comparison is internal to the dataset.

The freshwater-indicator idea that prompted this (*Vermamoeba vermiformis*, *Pristina
foreli*, *Lecane*, *Cypridopsis* dominating the deep COI blanks) is a SPECIAL CASE of
Q1: tapwater is not drawn from the sampled habitat, so it is compositionally an
outlier. The general test catches it without being told what tapwater looks like, and
would equally catch sterilised seawater used as a blank in a study where the habitat
is a freshwater lake. Useful as a confirmatory read-out for this run; not a
dependency.

## Suggested shape in TaxaFlag

    validate_controls(input_df, event_col, taxon_col, reads_col,
                      control_samples, site_col = NULL, ...)
        -> per-column verdict + per-site power, two-sided

    flag_contaminant(..., require_control_evidence = TRUE, site_col = NULL)
        -> adds the no_evidence / carryover states and the site-breadth discriminant,
           with the evidence columns carried through

`require_control_evidence` defaults FALSE for backward compatibility but should be
TRUE in new workflows; when FALSE it must warn that ESVs with no control observations
are being scored on shrinkage alone.

## Before any of this is trusted

Prove BOTH directions on real data, as with every other guard in this project:
  - it FLAGS a deliberately mislabelled column (relabel a known sample as a control)
  - it STAYS SILENT on a clean control set
A check that only demonstrates the first is half-tested, and the half it skips is the
one that gets it switched off.
